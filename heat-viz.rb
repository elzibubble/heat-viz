#!/usr/bin/ruby
# vim: set ts=2 sw=2:

require 'rubygems'
require './graphviz'
require 'mustache'
require 'yaml'
require 'fileutils'
require 'optparse'
require 'ostruct'
require 'pp'


########## TEMPLATE FORMAT #############

LANG_CFN = OpenStruct.new
LANG_CFN.version = /2012-12-12|ocata|pike/
LANG_CFN.get_resource = 'Ref'
LANG_CFN.get_param = 'Ref'
LANG_CFN.description = 'Description'
LANG_CFN.parameters = 'Parameters'
LANG_CFN.outputs = 'Outputs'
LANG_CFN.resources = 'Resources'
LANG_CFN.type = 'Type'
LANG_CFN.properties = 'Properties'
LANG_CFN.metadata = 'Metadata'
LANG_CFN.depends_on = 'DependsOn'
LANG_CFN.get_attr = 'Fn::GetAtt'

LANG_HOT = OpenStruct.new
LANG_HOT.version = /2013-05-23|ocata|pike/
LANG_HOT.get_resource = 'get_resource'
LANG_HOT.get_param = 'get_param'
LANG_HOT.description = 'description'
LANG_HOT.parameters = 'parameters'
LANG_HOT.outputs = 'outputs'
LANG_HOT.resources = 'resources'
LANG_HOT.type = 'type'
LANG_HOT.properties = 'properties'
LANG_HOT.metadata = 'metadata'
LANG_HOT.depends_on = 'depends_on'
LANG_HOT.get_attr = 'get_attr'

def get_lang(data)
  if not LANG_CFN.version.match(data["HeatTemplateFormatVersion"]).nil?
    LANG_CFN
  elsif not LANG_HOT.version.match(data["heat_template_version"]).nil?
    LANG_HOT
  else
    abort("Unrecognised HeatTemplateFormatVersion: #{version}")
  end
end


########## LOAD DATA #############

def load_data(file, filter)
  fdata = YAML.load(file)
  lang = get_lang(fdata)

  fdata = fdata[lang.resources].find_all {|item|
    case item[1][lang.type]
    when /OS::Heat::Structured/ then true
    when /OS::Nova::Server/ then true
    else false
    end
  }

  g = Graph.new
  es = []
  g[:ranksep] = 2.0
  g[:tooltip] = "Heat dependencies"
  fdata.each {|item|
    key = item[0]
    node = g.get_or_make(key)
    properties = item[1][lang.properties]
    config = properties["config"]

    type = item[1][lang.type]
    case type
    when /deployment/i
      node[:shape] = 'box'
      if properties["signal_transport"] != "NO_SIGNAL"
        node[:peripheries] = 2
      end
    when /config/i
      node[:shape] = 'oval'
      if config["completion-signal"] != nil
        node[:peripheries] = 2
      end
    when /server/i then 'box3d'
    else abort 'Unexpected type'
    end

    deps = item[1][lang.depends_on] || []
    deps.each() {|dep|
      es.push [key, dep]
    }

    if config
      ref = config[lang.get_resource]
      if ref
        es.push [ref, key]
      end
    end
  }

  es.each {|e|
    src, dst = e
    src_node = g.get(src)
    dst_node = g.get(dst)
    if filter.match(src).nil? or filter.match(dst).nil?
      puts "Filter out #{src}/#{dst} as non matching"
      next
    end
    if src_node == nil
      puts "Edge from unknown node: #{src}"
      next
    elsif dst_node == nil
      puts "Edge to unknown node: #{dst}"
      next
    end
    g.add GEdge[src_node, dst_node]
  }

  #g.nodes.each {|node|
  #  # Hack - remove anything with 1 in it because it's a scaled thing
  #  if node.key =~ /[1-9]/
  #    g.cut node
  #  end

  #  # TODO Drop unconnected nodes from graph
  #  not neighbors(node).empty? or g.cut node
  #}

  g
end


########## DECORATE ###########

def hsv(h,s,v)
  "%0.3f,%0.3f,%0.3f" % [h.to_f/360, s.to_f/100, v.to_f/100]
end
def palette(n, s, v)
  0.upto(n-1).map {|h|
    hsv(h*(360/n), s, v)
  }
end

def rank_node(node)
  case node.label
  when /::/ then :sink
  when /-core/ then :core
  end
end

def decorate(graph, tag=nil, decors)
  nhues = palette(decors.size, 30, 95)
  graph.nodes.each {|node|
    label = node.key
    node[:URL] = "focus-#{node.node}.html"

    if label =~ /(.*)-core/
      node[:group] = "#$1"
    else
      node[:group] = label
    end

    setfill = lambda {|pat, color|
      node[:fillcolor] = color if label =~ pat
      node[:style] = :filled if label =~ pat
    }
    ix = 1
    decors.each do |decor|
      setfill[/#{decor}/i, nhues[ix]]; ix += 1
    end
  }

  # ehues = palette(5, 80.9, 69.8)
  graph.edges.each {|edge|
    if edge.snode[:shape] == 'box' and edge.dnode[:shape] == 'box'
      edge[:penwidth] = 2.0
    end
  }

  graph
end


########## RENDER #############

def write(graph, filename)
  Mustache.template_file = 'diagram.mustache'
  view = Mustache.new
  view[:now] = Time.now.strftime("%Y.%m.%d %H:%M:%S")

  view[:title] = "Heat dependencies"
  view[:dotdata] = g2dot(graph)

  path = filename
  File.open(path, 'w') do |f|
    f.puts view.render
  end
end

def en_join(a)
  case a.count
  when 0 then "none"
  when 1 then a.first
  else
    a.slice(0, a.count-1).join(", ") +" and #{a.last}"
  end
end


########## OPTIONS #############

options = OpenStruct.new
options.format = :hot
options.output_filename = "heat-deps.html"
OptionParser.new do |o|
  options.filter = /.*/
  options.decors = ['compute', 'controller', 'storage']
  o.banner = "Usage: heat-viz.rb [options] heat.yaml"
  o.on("-o", "--output [FILE]", "Where to write output") do |fname|
    options.output_filename = fname
  end
  o.on("-f", "--filter [regex]", "Filter graph nodes (default .*)") do |filter|
    options.filter = /#{filter}/
  end
  o.on("-d", "--decors [FOO,BAR]", "Tags (steps/roles) for palete") do |decors|
    options.decors = decors.split(',')
  end
  o.on_tail("-h", "--help", "Show this message") do
    puts o
    exit
  end
end.parse!
if ARGV.length != 1
  abort("Must provide a Heat template")
end
options.input_filename = ARGV.shift

if !File.file? options.input_filename
  raise "Not a file: #{options.input_filename}"
end

graph = nil
File.open(options.input_filename) {|file|
  graph = load_data(file, options.filter)
}

graph = decorate(graph, nil, options.decors)
write(graph, options.output_filename)
