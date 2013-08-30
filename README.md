#OpenStreeMap Parser
This parser takes a **JSON** produced by an Overpass API query and transform it into a bulk insert for **MongoDB**.

##Usage
###Query
First, you need to have an Overpass server running with a database loaded. Especially, you need both `--osm-base` and `--areas` generated.

Then, you need to run a query like this to generate parsable results:

```
[timeout:1800][maxsize:2147483648][out:json];
area[name="Italia"];
node(area)[place~"village|town|city"][name~"^(A|B)"];
foreach->.p(
  .p is_in->.a;
  area.a[admin_level~"9|8|7"]->.c;
  .p out;
  foreach.c->.ar(
    .ar out;
        rel(pivot.ar)->.rel;
        way(r.rel);
        node(w);
        out;
  );
);
```

Out format ( **json** ) and out *instructions order* are important.

Note that `[name~"^(A|B)"]` is a parameter used to split data in smaller chunks. In this way for a country you'll get a ~50mb file for each letter. Be warned.

> `m1.medium` amazon instances works better with 3-4 letters.
> 
> `m1.small` are suitable for 1 letter.

###Parser (first step)
After producing the `json` file, you need to run `./parser.rb <input.json> <output.js> <error.json>`

* `error.json` isn't required, and the default `error.log` will be generated. This file is needed in the second step.

* `output.js` is a command runnable with the Mongo shell simply with `mongo < output.js`. It will bulk insert data in `areas` collection.

###Filler (second step)
Due to Overpassi API query limits, some areas may be available but not generated in the first step. The **filler** will run some particular query for each place found in the `input.json` and put into `error.json`, generating other areas.

You'll need to run `./filler.rb <errors.json> <recovered_output.js> <filler_errors.json>` in the same folder where `osm3s_query` is.

Currently, the methods it use are various.

####1) Direct area name
The filler will try to run this query:

```
[out:json];
area[name="#{error[:name]}"][type="boundary"]->.c;
rel(pivot.c)->.rel;
way(r.rel);
node(w);
.c out;
out;
```

Where `#{error[:name]}` is the place name found in the JSON.

####2) Approximate by place tag
The fill approximate the radius based on `error[:type]` (`place` tag in OSM), using this comparison table:

| Type | Radius | Km |
| ---- | ------ | -- |
| isolated_dwelling | 100m | 0,1 |
| hamlet | 500m | 0,5 |
| village, locality, island | 1000m | 1 |
| town | 5000m |  5 |
| city | 20000m | 20 |