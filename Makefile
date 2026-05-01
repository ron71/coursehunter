SERVICES_DIR := services
COMPOSE_FILE := docker-compose.yml

.DEFAULT_GOAL := help

.PHONY: help build clean test install run stop logs

help:
	@echo "CourseHunter — available targets:"
	@echo ""
	@echo "  build       Build all services (skip tests)"
	@echo "  install     Build all services and run tests"
	@echo "  clean       Clean all build artifacts"
	@echo "  test        Run tests for all services"
	@echo "  run         Start all services with Docker Compose"
	@echo "  stop        Stop all running containers"
	@echo "  logs        Tail logs from all containers"

build:
	cd $(SERVICES_DIR) && mvn clean package -DskipTests

install:
	cd $(SERVICES_DIR) && mvn clean install

clean:
	cd $(SERVICES_DIR) && mvn clean

test:
	cd $(SERVICES_DIR) && mvn test

run:
	docker compose -f $(COMPOSE_FILE) up --build -d

stop:
	docker compose -f $(COMPOSE_FILE) down

logs:
	docker compose -f $(COMPOSE_FILE) logs -f
