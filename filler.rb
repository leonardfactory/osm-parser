#!/usr/bin/env ruby
require 'yajl'
require 'geo-distance'
require_relative 'osm'

module OSM
  module Filler
    
    # Filler class
    class Filler
      
      def initialize(writer, logger)
        @writer = writer
        @logger = logger
        @parser = Yajl::Parser.new(:symbolize_keys => true)
        @parser.on_parse_complete = method(:object_parsed)
        
        @temp_file = nil
      end
    
      def object_parsed(obj)
        obj[:errors].each do |error|
          
          puts "Processing #{error[:name]}"
          
          # Write temporary query
          @temp_file = File.open('/home/ubuntu/bin/bin/query_temp.in', 'w') # overwrite
          @temp_file.puts("[out:json];
            area[name=\"#{error[:name]}\"][type=\"boundary\"]->.c;
            rel(pivot.c)->.rel;
            way(r.rel);
            node(w);
            .c out;
            out;");
          @temp_file.close
          
          # Execute
          json_str = `/home/ubuntu/bin/bin/osm3s_query --db-dir=/osm/db < /home/ubuntu/bin/bin/query_temp.in`
          
          # Parse
          json = Yajl::Parser.parse(json_str)
          
          if(json["elements"] == nil || json["elements"].size == 0)
            @logger.log(error)
          else
            puts json["elements"][0]
            
            area = {}
            center = {}
            coords = []
            
            box = { :top => 0.0, :left => 0.0, :right => 0.0, :bottom => 0.0 }
            
            json["elements"].each do |element|
              tags = element.key?("tags") ? element["tags"] : nil
              
              if element["type"] == 'area'
                area[:name] = error[:name]
                area[:type] = error[:type]
                area[:center] = error[:center]
                center = { :lat => error[:center][1], :lon => error[:center][0] }
              
              elsif element["type"] == 'node'
                distance = GeoDistance::Haversine.geo_distance( center[:lat], center[:lon],
                                                                element["lat"], element["lon"]).to_meters;  
                coords.push(distance);
                
                # Checking box (lat is N-S, lon is E-O)
                box[:bottom]  = [element["lat"], box[:bottom]].min
                box[:top]     = [element["lat"], box[:top]].max
                box[:left]    = [element["lon"], box[:left]].min
                box[:right]   = [element["lon"], box[:right]].max
              end
            end
            
            puts "[Done]"
            
            # Check before if center is contained inside the area processed
            inside =  box[:bottom] < center[:lat] &&
                      box[:top] > center[:lat] &&
                      box[:left] < center[:lon] &&
                      box[:right] > center[:lon]
            
            if inside
              # Now process points and save to our output
              distance_avg = coords.inject(0.0) { |sum, dist| sum + dist }.to_f / coords.size
              area[:radius] = distance_avg * 1.2 # Something moar is okay
              area[:geometry] = { :type => 'Polygon', :coordinates => [ OSM::Converter.radius2poly(center, area[:radius]) ] }
              @writer.put(area)
            else
              @logger.log(error)
            end
          end
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
        @filler = OSM::Filler::Filler.new(writer, logger)
      end
    
      def parse
        File.open(@file).each do |line|
          @filler.receive_data(line)
        end
      end
    end
    
    # Start the filler
    def self.read_and_parse(from, to, log)
      writer = OSM::Writer.new(to)
      logger = OSM::Logger.new(log)
      reader = OSM::Filler::Reader.new(from, writer, logger)
      reader.parse
    end
  end
end

OSM::Filler.read_and_parse(ARGV[0], ARGV[1], ARGV.size > 2 ? ARGV[2] : 'filler.log')