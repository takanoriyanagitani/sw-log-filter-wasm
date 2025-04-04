#!/bin/sh

swift \
	package \
	plugin \
	--allow-writing-to-package-directory \
	swiftlint \
	--strict \
	--progress \
	./Sources
