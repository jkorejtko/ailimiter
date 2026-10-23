.PHONY: build run install clean

build:
	@./scripts/build_app.sh

run:
	@./scripts/build_app.sh run

install:
	@./scripts/build_app.sh install

clean:
	@rm -rf build dist
