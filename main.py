from fastapi import FastAPI
from pydantic import BaseModel
from sqlalchemy import create_engine, Column, Integer, String
from sqlalchemy.orm import declarative_base, sessionmaker
import os

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://postgres:postgres@localhost:5432/scooter_db")

engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

class Scooter(Base):
    __tablename__ = "scooters"
    id = Column(Integer, primary_key=True, index=True)
    brand = Column(String, index=True)
    battery_level = Column(Integer)

Base.metadata.create_all(bind=engine)

app = FastAPI(title="Scooter Rental API")

class ScooterCreate(BaseModel):
    brand: str
    battery_level: int

@app.post("/scooters/")
def add_scooter(scooter: ScooterCreate):
    db = SessionLocal()
    db_scooter = Scooter(brand=scooter.brand, battery_level=scooter.battery_level)
    db.add(db_scooter)
    db.commit()
    db.refresh(db_scooter)
    return db_scooter

@app.get("/scooters/")
def get_scooters():
    db = SessionLocal()
    return db.query(Scooter).all()