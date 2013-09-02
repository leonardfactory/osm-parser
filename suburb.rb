#!/usr/bin/env ruby
require 'yajl'
require 'geo-distance'
require_relative 'osm'

BIN_FOLDER    = "/home/ubuntu/bin/bin"
RESULT_FOLDER = "/osm/parser-results"

module OSM
  module Suburb
    
    # A Parser exclusively for Suburbs & Neighbourhoods
    class Parser
      
      @@values = {
        'neighbourhood'   => 500.0,
        'suburb'          => 500.0
      }
      
      def initialize(writer, logger)
        @writer = writer
        @logger = logger
        @parser = Yajl::Parser.new(:symbolize_keys => true)
        @parser.on_parse_complete = method(:object_parsed)
      end
      
      def object_parsed(obj)
        obj[:elements].each do |element|
          area   = {}
          center = {}
          
          area[:name] = element[:tags][:name]
          area[:type] = element[:tags][:place]
          area[:center] = [element[:lon], element[:lat]]
          center = { :lat => element[:lat], :lon => element[:lon] }
          
          area[:radius] = @@values[area[:type]]
          area[:geometry] = { :type => 'Polygon', :coordinates => [ OSM::Converter.radius2poly(center, area[:radius]) ] }
          area[:approximate] = true
          @writer.put(area)
        end
        
        @logger.done!
        @writer.done!
      end
      
      def receive_data(data)
        @parser << data
      end
    end
    
    # A Reader to push streamed file (JSON now) inside
    # the parser.
    class Reader
      def initialize(file_path, writer, logger)
        @file = file_path
        @suburb = OSM::Suburb::Parser.new(writer, logger)
      end
    
      def parse
        File.open(@file).each do |line|
          @suburb.receive_data(line)
        end
      end
    end
    
    def self.generate!
      # Write temp query
      temp_query = File.open("#{BIN_FOLDER}/query_temp_suburb.in", 'w')
      temp_query.puts("[out:json][timeout:900];
                        area[name=\"Italia\"];
                        node(area)[place~\"^(neighbourhood|suburb)$\"];
                        out;")
      temp_query.close
      
      # And execute it
      Dir.chdir(BIN_FOLDER) do
        generated = system("./osm3s_query --db-dir=/osm/db/ < #{BIN_FOLDER}/query_temp_suburb.in > #{RESULT_FOLDER}/suburb.json")
      end
    end
    
    def self.read_and_parse(from, to, log)
      writer = OSM::Writer.new(to)
      logger = OSM::Logger.new(log)
      reader = OSM::Suburb::Reader.new(from, writer, logger)
      reader.parse
    end
  end
end

if !File.exists?("#{RESULT_FOLDER}/suburb.json")
  OSM::Suburb.generate!
end

OSM::Suburb.read_and_parse("#{RESULT_FOLDER}/suburb.json", ARGV[0], ARGV.size > 1 ? ARGV[1] : 'suburb-parser.log')