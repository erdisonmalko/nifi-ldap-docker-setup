.PHONY: set-up, set-up-y, down, restart, logs

set-up:
	powershell -NoProfile -ExecutionPolicy Bypass -Command "& './scripts/windows/setup-nifi.ps1'"

set-up-y:
	powershell -NoProfile -ExecutionPolicy Bypass -Command "& './scripts/windows/setup-nifi.ps1' -SkipConfirmation"

down:
	docker-compose -f docker-compose.yml down

restart:
	docker-compose -f docker-compose.yml restart

logs:
	docker-compose -f docker-compose.yml logs -f nifi