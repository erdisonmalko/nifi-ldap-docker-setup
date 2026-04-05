.PHONY: set-up set-up-y down restart logs

set-up:
	bash ./scripts/linux/setup-nifi.sh

set-up-y:
	bash ./scripts/linux/setup-nifi.sh --skip-confirmation

down:
	docker-compose -f docker-compose.yml down

restart:
	docker-compose -f docker-compose.yml restart

logs:
	docker-compose -f docker-compose.yml logs -f nifi