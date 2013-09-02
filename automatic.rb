#!/usr/bin/env ruby
require 'yajl'
require 'geo-distance'
require_relative 'osm'

chunks = [
  { :query => 'A',      :prefix => 'a'},
  { :query => 'B',      :prefix => 'b' },
  { :query => 'C',      :prefix => 'c' },
  { :query => 'D|E|F',  :prefix => 'def'},
  { :query => 'G|H|I',  :prefix => 'ghi'},
  { :query => 'J|K|L',  :prefix => 'jkl'},
  { :query => 'M|N',    :prefix => 'mn'},
  { :query => 'O',      :prefix => 'o' },
  { :query => 'P|Q|R',  :prefix => 'pqr'},
  { :query => 'S|T|U',  :prefix => 'stu'},
  { :query => 'V|W|X|Y|Z', :prefix => 'vwxyz'}
]

RESULTS_FOLDER  = "/osm/parser-results"
BIN_FOLDER      = "/home/ubuntu/bin/bin"
PARSER_FOLDER   = "/home/ubuntu/parser/osm-parser"

logger = OSM::Logger.new('automatic-log.json')

chunks.each do |chunk|
  
  # First, run OSM query to generate base JSON
  query_ok = false
  
  Dir.chdir(BIN_FOLDER) do
    
    # Write query
    file = File.open('query_chunk.in', 'w')
    file.puts("[timeout:1800][maxsize:2147483648][out:json];
                area[name=\"Italia\"];
                node(area)[place~\"village|hamlet|town|city\"][name~\"^(#{chunk[:query]})\"];
                foreach->.p(
                  .p is_in->.a;
                  area.a[admin_level~\"9|8|7\"]->.c;
                  .p out;
                  foreach.c->.ar(
                    .ar out;
                        rel(pivot.ar)->.rel;
                        way(r.rel);
                        node(w);
                        out;
                  );
                );")
    file.close
    
    if File.exists?("#{RESULTS_FOLDER}/chunk_#{chunk[:prefix]}.json")
      # Yet done
      query_ok = true
    else
      # Run it
      query_ok = system("./osm3s_query --db-dir=/osm/db/ < query_chunk.in > #{RESULTS_FOLDER}/chunk_#{chunk[:prefix]}.json")
    end
  end
    
  if query_ok
    # Now parse
    parsed = false
    Dir.chdir(PARSER_FOLDER) do
      parsed = system("./parser.rb #{RESULTS_FOLDER}/chunk_#{chunk[:prefix]}.json #{RESULTS_FOLDER}/#{chunk[:prefix]}_insert.js #{RESULTS_FOLDER}/#{chunk[:prefix]}_errors.json")
    end
    
    if parsed
      # And then run the filler
      filled = false
      Dir.chdir(BIN_FOLDER) do
        filled = system("./filler.rb #{RESULTS_FOLDER}/#{chunk[:prefix]}_errors.json #{RESULTS_FOLDER}/#{chunk[:prefix]}_recovered.js #{RESULTS_FOLDER}/#{chunk[:prefix]}_filler_errors.json")
      end
      
      if filled
        logger.log({ :done => "Completed", :chunk => chunk })
      else
        logger.log({ :error => "Cannot fill", :chunk => chunk })
      end
      
    else
      logger.log({ :error => "Cannot parse", :chunk => chunk })
    end
    
  else
    logger.log({ :error => "Cannot run query", :chunk => chunk })
  end
end

logger.done!