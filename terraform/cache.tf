variable "cache_enabled" {
  description = "Чи вмикати кеш у застосунку (перемикайте для порівняння в docs/CACHE.md)"
  type        = bool
  default     = true
}

variable "cache_ttl_seconds" {
  description = "TTL запису в кеші, секунди (за умовою лаби 30-60)"
  type        = number
  default     = 45
}

variable "redis_node_type" {
  description = "Тип вузла ElastiCache"
  type        = string
  default     = "cache.t4g.micro"
}

resource "aws_elasticache_subnet_group" "redis" {
  name       = "scooter-redis-subnets"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]
}

# Redis доступний тільки з контейнерів API
resource "aws_security_group" "redis_sg" {
  name        = "redis_security_group"
  description = "Allow Redis access from API only"
  vpc_id      = aws_vpc.main_vpc.id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.api_sg.id]
  }
}

resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "scooter-redis"
  engine               = "redis"
  engine_version       = "7.1"
  node_type            = var.redis_node_type
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.redis.name
  security_group_ids   = [aws_security_group.redis_sg.id]
}
