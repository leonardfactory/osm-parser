#!/usr/bin/env ruby
require "rexml/document"

file = File.new("filas.places.xml")
doc = REXML::Document.new file

