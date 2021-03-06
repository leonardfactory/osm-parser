#!/usr/bin/env ruby
require 'yajl'
require 'geo-distance'
require_relative 'osm'

# Module to process OSM generated json.
module OSM
  
  # Parser to read OSM Jsons and generate areas from them
  class Parser
    
    # Finite-states machine
    START       = 0
    NODE        = 1
    AREA        = 2
    AREA_SKIP   = 3
    
    # Variables for state
    @area       = {}
    @center     = {}
    @coords     = []
    
    # Debugging
    @@debug     = false
    
    def initialize(writer, logger)
      @writer = writer
      @logger = logger
      @parser = Yajl::Parser.new(:symbolize_keys => true)
      @parser.on_parse_complete = method(:object_parsed)
    end
    
    def update_area(element, tags)
      @coords = []
      @area   = {}
      @center = {}
      
      @area[:name] = tags[:name]
      @area[:type] = tags[:place]
      @area[:center] = [element[:lon], element[:lat]]
      @center = { :lat => element[:lat], :lon => element[:lon] }
    end
    
    def clog(message)
      if @@debug 
        puts message
      end
    end 
    
    # When stream is loaded, parse the returned JSON object
    def object_parsed(obj)       
      status = OSM::Parser::START
    
      obj[:elements].each do |element|
        
        # Keeps a shorthand to tags
        tags = element.key?(:tags) ? element[:tags] : nil
        
        # Starting here!
        if element[:type] == 'node' && tags != nil && tags.key?(:place) && status == OSM::Parser::START
          clog('Changed to NODE')
          status = OSM::Parser::NODE
          update_area(element, tags)
        
        # We've found an area? Let check if it's ok, then go ahead
        elsif element[:type] == 'area' && status == OSM::Parser::NODE
          clog('Changed to AREA_SKIP')
          status = OSM::Parser::AREA_SKIP
        
          if tags[:name] == @area[:name]
            clog('Changed to AREA')
            status = OSM::Parser::AREA
          end
        
        # Too much areas. Need to skip + @todo
        elsif element[:type] == 'area' && status == OSM::Parser::AREA
          clog('Changed to AREA_SKIP')
          status = OSM::Parser::AREA_SKIP # skip because there points (nodes) not usable
        
        # We didn't process previous nodes, however we must reset everything to keep going on.
        elsif element[:type] == 'node' && tags != nil && tags.key?(:place) && status == OSM::Parser::AREA_SKIP
          clog('Reeeeset.')
          # Logs that this node/area hasn't been processed
          @logger.log(@area)
          # Reset
          status = OSM::Parser::NODE
          update_area(element, tags)
        
        # Push some coords baby
        elsif element[:type] == 'node' && (tags == nil || !tags.key?(:place)) && status == OSM::Parser::AREA
          distance = GeoDistance::Haversine.geo_distance( @center[:lat], @center[:lon],
                                                          element[:lat], element[:lon]).to_meters;
          @coords.push(distance);
        
        # So, coords are over. Process them and forge this shining bright area. Then, restart.
        elsif element[:type] == 'node' && tags != nil && tags.key?(:place) && status == OSM::Parser::AREA
          clog('Changed to NODE (restart)')
          distance_avg = @coords.inject(0.0) { |sum, dist| sum + dist }.to_f / @coords.size
          @area[:radius] = distance_avg * 1.2 # Something moar is okay
          @area[:geometry] = { :type => 'Polygon', :coordinates => [ OSM::Converter.radius2poly(@center, @area[:radius]) ] }
          @writer.put(@area)
          
          # Now reset.
          status = OSM::Parser::NODE
          update_area(element, tags)
        end
        
        # Debug
        if @@debug && tags != nil && tags.key?(:name) && tags.key?(:place)
          puts "Processing `#{tags[:name]}`"
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
      @parser = OSM::Parser.new(writer, logger)
    end
    
    def parse
      File.open(@file).each do |line|
        @parser.receive_data(line)
      end
    end
  end
  
  def self.read_and_parse(from, to, log)
    writer = OSM::Writer.new(to)
    logger = OSM::Logger.new(log)
    reader = OSM::Reader.new(from, writer, logger)
    reader.parse
  end
end

OSM.read_and_parse(ARGV[0], ARGV[1], ARGV.length > 2 ? ARGV[2] : 'parser.log')