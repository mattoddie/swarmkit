# Set an output prefix, which is the local directory if not specified.
PREFIX?=$(shell pwd)

# Used to populate version variable in main package.
VERSION=$(shell git describe --match 'v[0-9]*' --dirty='.m' --always)

# Project packages.
PACKAGES=$(shell go list ./... | grep -v /vendor/)

GO_LDFLAGS=-ldflags "-X `go list ./version`.Version=$(VERSION)"

.PHONY: clean all fmt vet lint build test binaries setup
.DEFAULT: default
all: fmt vet lint build binaries test

AUTHORS: .mailmap .git/HEAD
	git log --format='%aN <%aE>' | sort -fu > $@

# This only needs to be generated by hand when cutting full releases.
version/version.go:
	./version/version.sh > $@

${PREFIX}/bin/swarmctl: version/version.go $(shell find . -type f -name '*.go')
	@echo "+ $@"
	@go build  -o $@ ${GO_LDFLAGS}  ${GO_GCFLAGS} ./cmd/swarmctl

${PREFIX}/bin/swarmd: version/version.go $(shell find . -type f -name '*.go')
	@echo "+ $@"
	@go build  -o $@ ${GO_LDFLAGS}  ${GO_GCFLAGS} ./cmd/swarmd

${PREFIX}/bin/protoc-gen-gogoswarm: version/version.go $(shell find . -type f -name '*.go')
	@echo "+ $@"
	@go build  -o $@ ${GO_LDFLAGS}  ${GO_GCFLAGS} ./cmd/protoc-gen-gogoswarm

setup:
	@echo "+ $@"
	@go get -u github.com/golang/lint/golint

generate: ${PREFIX}/bin/protoc-gen-gogoswarm
	PATH=${PREFIX}/bin/:${PATH} go generate ${PACKAGES}

checkprotos: generate
	@echo "+ $@"
	@test -z "$$(git status --short | grep ".pb.go" | tee /dev/stderr)" || \
		(echo "+ please run 'make generate' when making changes to proto files" && false)

# Depends on binaries because vet will silently fail if it can't load compiled
# imports
vet: binaries
	@echo "+ $@"
	@go vet ${PACKAGES}

fmt:
	@echo "+ $@"
	@test -z "$$(gofmt -s -l . | grep -v vendor/ | grep -v ".pb.go$$" | tee /dev/stderr)" || \
		(echo "+ please format Go code with 'gofmt -s'" && false)
	@test -z "$$(find . -path ./vendor -prune -o -name '*.proto' -type f -exec grep -Hn -e "^ " {} \; | tee /dev/stderr)" || \
		(echo "+ please indent proto files with tabs only")

lint:
	@echo "+ $@"
	@test -z "$$(golint ./... | grep -v vendor/ | grep -v ".pb.go:" | tee /dev/stderr)"

build:
	@echo "+ $@"
	@go build -tags "${DOCKER_BUILDTAGS}" -v ${GO_LDFLAGS} ./...

test:
	@echo "+ $@"
	@go test -race -tags "${DOCKER_BUILDTAGS}" ${PACKAGES}

binaries: ${PREFIX}/bin/swarmctl ${PREFIX}/bin/swarmd ${PREFIX}/bin/protoc-gen-gogoswarm
	@echo "+ $@"

clean:
	@echo "+ $@"
	@rm -rf "${PREFIX}/bin/swarmctl" "${PREFIX}/bin/swarmd" "${PREFIX}/bin/protoc-gen-gogoswarm"

coverage: 
	@echo "+ $@"
	@for pkg in ${PACKAGES}; do \
		go test -tags "${DOCKER_BUILDTAGS}" -test.short -coverprofile="../../../$$pkg/coverage.txt" -covermode=count $$pkg; \
	done
