import json
import logging
import os

import redis
from fastapi import Depends, FastAPI, Response
from pydantic import BaseModel
from sqlalchemy import Column, Integer, String, create_engine, func
from sqlalchemy.orm import declarative_base, sessionmaker

logger = logging.getLogger("scooter-api")

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://postgres:postgres@localhost:5432/scooter_db")

# --- Кеш (lab 2, завдання 5) ---
CACHE_ENABLED = os.getenv("CACHE_ENABLED", "false").lower() == "true"
CACHE_TTL_SECONDS = int(os.getenv("CACHE_TTL_SECONDS", "45"))
REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379/0")

# pool_size * кількість інстансів (max 4) має бути < max_connections у db.t3.micro (~80)
engine = create_engine(DATABASE_URL, pool_size=5, max_overflow=5, pool_pre_ping=True)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


class Scooter(Base):
    __tablename__ = "scooters"
    id = Column(Integer, primary_key=True, index=True)
    brand = Column(String, index=True)
    battery_level = Column(Integer)


Base.metadata.create_all(bind=engine)

# Короткі таймаути: якщо Redis недоступний, застосунок деградує до роботи без кешу, а не падає
cache = None
if CACHE_ENABLED:
    cache = redis.Redis.from_url(REDIS_URL, socket_connect_timeout=0.3, socket_timeout=0.3)

app = FastAPI(title="Scooter Rental API v2.0")


class ScooterCreate(BaseModel):
    brand: str
    battery_level: int


def get_db():
    # Сесія закривається після кожного запиту; раніше вона протікала і вичерпувала пул з'єднань
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/scooters/")
def add_scooter(scooter: ScooterCreate, db=Depends(get_db)):
    db_scooter = Scooter(brand=scooter.brand, battery_level=scooter.battery_level)
    db.add(db_scooter)
    db.commit()
    db.refresh(db_scooter)
    return db_scooter


@app.get("/scooters/")
def get_scooters(limit: int = 200, db=Depends(get_db)):
    """Остані limit самокатів (без кешу)."""
    limit = max(1, min(limit, 1000))
    return db.query(Scooter).order_by(Scooter.id.desc()).limit(limit).all()


REPORT_CACHE_KEY = "cache:scooters:report"


def _build_report(db):
    # Найважчий читальний запит: GROUP BY по всій таблиці, повне сканування
    rows = (
        db.query(
            Scooter.brand,
            func.count(Scooter.id),
            func.avg(Scooter.battery_level),
            func.min(Scooter.battery_level),
        )
        .group_by(Scooter.brand)
        .order_by(Scooter.brand)
        .all()
    )
    return [
        {"brand": b, "count": c, "avg_battery": float(a) if a is not None else None, "min_battery": m}
        for b, c, a, m in rows
    ]


@app.get("/scooters/report")
def scooters_report(db=Depends(get_db)):
    """Звіт по брендах. Cache-aside: Redis -> (miss) -> БД -> запис у Redis з TTL."""
    if cache is not None:
        try:
            cached = cache.get(REPORT_CACHE_KEY)
            if cached is not None:
                cache.incr("stats:hits")
                return Response(content=cached, media_type="application/json", headers={"X-Cache": "HIT"})
            cache.incr("stats:misses")
        except redis.RedisError as e:
            logger.warning("redis read failed, falling back to DB: %s", e)

    report = _build_report(db)
    payload = json.dumps(report)

    if cache is not None:
        try:
            cache.set(REPORT_CACHE_KEY, payload, ex=CACHE_TTL_SECONDS)
        except redis.RedisError as e:
            logger.warning("redis write failed: %s", e)

    return Response(content=payload, media_type="application/json", headers={"X-Cache": "MISS"})


@app.get("/cache/stats")
def cache_stats():
    """Загальний (для всіх інстансів) hit rate з Redis."""
    if cache is None:
        return {"enabled": False}
    hits = int(cache.get("stats:hits") or 0)
    misses = int(cache.get("stats:misses") or 0)
    total = hits + misses
    return {
        "enabled": True,
        "ttl_seconds": CACHE_TTL_SECONDS,
        "hits": hits,
        "misses": misses,
        "hit_rate": round(hits / total, 4) if total else None,
    }


@app.post("/cache/stats/reset")
def cache_stats_reset():
    if cache is not None:
        cache.delete("stats:hits", "stats:misses")
    return {"reset": True}
