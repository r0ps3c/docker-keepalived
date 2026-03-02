PKGNAME:=keepalived
TAG:=main
DOCKERFILE:=Dockerfile

.PHONY: build test-structure test-standalone test-integration test-all clean-test version show-version

build:
	docker build --pull -t $(PKGNAME):$(TAG) -f $(DOCKERFILE) .

test-structure: build
	./tests/structure.sh $(PKGNAME):$(TAG)

test-standalone: build
	./tests/standalone.sh $(PKGNAME):$(TAG)

test-integration: build
	./tests/integration.sh $(PKGNAME):$(TAG)

test-all: test-structure test-standalone test-integration

clean-test:
	docker rm -f keepalived-test-* 2>/dev/null || true
	docker volume rm -f keepalived-test-* 2>/dev/null || true
	docker network rm keepalived-test-* 2>/dev/null || true

version: build
	@docker run --rm --entrypoint sh $(PKGNAME):$(TAG) -c 'apk info keepalived 2>/dev/null | grep "^keepalived-" | head -1 | cut -d- -f2 | cut -dr -f1'

show-version: build
	@FULL_VER=$$(docker run --rm --entrypoint sh $(PKGNAME):$(TAG) -c 'apk info keepalived 2>/dev/null | grep "^keepalived-" | head -1 | cut -d- -f2 | cut -dr -f1'); \
	MAJOR_VER=$$(echo $$FULL_VER | cut -d. -f1); \
	echo "Full version: $$FULL_VER"; \
	echo "Major version: $$MAJOR_VER"
