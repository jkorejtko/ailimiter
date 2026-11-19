.PHONY: build run install test security clean

build:
	@bash scripts/build_app.sh

run:
	@bash scripts/build_app.sh run

install:
	@bash scripts/build_app.sh install

clean:
	@rm -rf build dist

test:
	@swift test --disable-xctest

security:
	@python3 scripts/check_secrets.py
