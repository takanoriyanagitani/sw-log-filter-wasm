#!/bin/sh

swift-format \
	format \
	--in-place \
	--recursive \
	--ignore-unparsable-files \
	--parallel \
	--color-diagnostics \
	./Sources \
	./Package.swift
