module OSM
  # A Writer where to store what we are doing here
  class Writer
    def initialize(file_path)
      @file = file_path
      @first_line = true
      @stream = File.open(@file, 'w')
      @encoder = Yajl::Encoder.new
      
      # Puts MongoDB bulk insert command
      @stream.puts("db.areas.insert([\n")
    end
    
    def put(hash)
      if !@first_line 
        @stream.puts(",")
      else
        @first_line = false
      end
      @encoder.encode(hash, @stream)
    end
    
    def done!
      # MongoDB closing insert command
      @stream.puts("\n])")
      @stream.close
    end
  end
  
  # Logger
  class Logger
    def initialize(file_path)
      @file = file_path
      @first_line = true
      @stream = File.open(@file, 'w')
      @encoder = Yajl::Encoder.new
      
      @stream.puts("{ \"errors\": [\n")
    end
    
    def log(hash)
      if !@first_line 
        @stream.puts(",")
      else
        @first_line = false
      end
      @encoder.encode(hash, @stream)
    end
    
    def done!
      @stream.puts("\n] }")
      @stream.close
    end
  end
  
  # Converter methods to handle units conversion
  module Converter
    module Along
      LON = 0
      LAT = 1
    end
    
    def self.meters2degrees(meters, along, lat)
  		rlat = lat * Math::PI / 180.0
  		degrees = (meters / (along == Along::LON ? (111412.84 * Math.cos(rlat)) : 111132.92))
  	  return degrees
    end
    
    def self.radius2poly(center, radius)
  		sides 		= radius < 1000.0 ? 4 : (radius < 20000.0 ? 6 : 8)
      apothem   = radius.to_f
      geometry  = []
      ifloat    = nil
      
      rotation  = (2.0 * Math::PI) / sides.to_f
      langle    = rotation / 2.0  # Angle used to calculate diagonal length. Half of rotation angle.
      length    = apothem / Math.cos(langle)
      
      sides.times do |i|
        ifloat = i.to_f
        
        geometry.push([
          center[:lon] + meters2degrees(length * Math.cos((ifloat * rotation) + langle), Along::LON, center[:lat]),
          center[:lat] + meters2degrees(length * Math.sin((ifloat * rotation) + langle), Along::LAT, center[:lat])
        ])
      end
      
      geometry.push(geometry[0])
		
  		return geometry
    end
  end
end