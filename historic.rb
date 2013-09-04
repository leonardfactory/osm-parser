#!/usr/bin/env ruby
require 'yajl'
require_relative 'osm'

BIN_FOLDER    = "/home/ubuntu/bin/bin"
RESULT_FOLDER = "/osm/parser-results"

module OSM
  module Historic
    class Parser
      def initialize(writer, logger)
        @writer = writer
        @logger = logger
        @parser = Yajl::Parser.new(:symbolize_keys => true)
        @parser.on_parse_complete = method(:object_parsed)
      end
      
      def get_radius(element)
        if element[:tags][:historic] == 'archaeological_site'
          return 600.0
        else
          return 400.0
        end
      end
      
      def object_parsed(obj)
        obj[:elements].each do |element|
          area   = {}
          center = {}
          
          area[:name] = element[:tags][:name]
          area[:type] = 'historic'
          area[:category] = element[:tags][:historic]
          area[:center] = [element[:lon], element[:lat]]
          center = { :lat => element[:lat], :lon => element[:lon] }
          
          area[:radius] = @@values[area[:type]]
          area[:geometry] = { :type => 'Polygon', :coordinates => [ OSM::Converter.radius2poly(center, area[:radius]) ] }
          area[:approximate] = true
          @writer.put(area)
        end
        
        @writer.done!
        @logger.done!
      end
      
      def receive_data(data)
        @parser << data
      end
    end
       
    def self.generate!
      temp_query = File.open("#{BIN_FOLDER}/query_temp_historic.in", 'w')
      temp_query.puts("[out:json][timeout:900];
                        area[name=\"Italia\"];
                        node(area)[historic];
                        out;")
      temp_query.close
      
      Dir.chdir(BIN_FOLDER) do
        generated = system("./osm3s_query --db-dir=/osm/db/ < #{BIN_FOLDER}/query_temp_historic.in > #{RESULT_FOLDER}/historic.json")
      end
    end 
    
    def self.read_and_parse(from, to, log)
      writer = OSM::Writer.new(to)
      logger = OSM::Logger.new(log)
      parser = OSM::Historic::Parser.new(writer, logger)
      reader = OSM::General::Reader.new(from, parser.method(:receive_data))
      reader.read!
    end
  end
end

if !File.exists?("#{RESULT_FOLDER}/historic.json")
  OSM::Historic.generate!
end

OSM::Historic.read_and_parse("#{RESULT_FOLDER}/historic.json", ARGV[0], ARGV.size > 1 ? ARGV[1] : 'historic-parser.log')