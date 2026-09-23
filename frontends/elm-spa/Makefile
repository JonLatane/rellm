.NOTPARALLEL:
# .DEFAULT_GOAL := default
# default: protos docs graphs
.PHONY: server stop_background_servers build review review_fix gen setup_proto_build protos

run: server

test: review
	npx elm-test

server:
	npx elm-spa server

format:
	npx elm-format

stop_background_servers:
	lsof -ti:1234 | xargs -r kill; sleep 1; lsof -ti:1234 || echo "port 1234 free"

build:
	npx elm-spa build

review: gen
	npx elm-review

review_fix: gen
	npx elm-review --fix-all

gen:
	npx elm-spa gen

setup_proto_build:
	yarn global add protoc-gen-elm

protos:
	protoc --elm_out=./src -I../../protos ../../protos/*.proto