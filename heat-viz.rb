#!/usr/bin/ruby
# vim: set ts=2 sw=2:

require 'rubygems'
require './graphviz'
require 'mustache'
require 'yaml'
require 'fileutils'


########## LOAD DATA #############

def load_data(file)
  fdata = YAML.load(file)
  fdata = fdata["Resources"].find_all {|item|
    item[1]["Type"] =~ /OS::Heat::Structured/
  }

  g = Graph.new
  g[:ranksep] = 2.0
  fdata.each {|item|
    key = item[0]
    node = g.get_or_make(key)

    type = item[1]["Type"]
    node[:shape] = (type =~ /deployment/i and 'box' or nil)

    deps = item[1]["DependsOn"] || []
    deps.each() {|dep|
      dst = g.get_or_make(dep)
      g.add GEdge[node, dst]
    }

    properties = item[1]["Properties"]
    if properties
      config = properties["config"]
      if config
        ref = config["Ref"]
        if ref
          src = g.get_or_make(ref)
          g.add GEdge[src, node]
        end
      end
    end
  }

  g.nodes.each {|node|
    # Hack - remove anything with 1 in it because it's a scaled thing
    if node.key =~ /1/
      g.cut node
    end
  }

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

def decorate(graph, tag=nil)
  nhues = palette(6, 30, 95)
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
    setfill[/controller/i, nhues[ix]]; ix += 1
    setfill[/compute/i, nhues[ix]]; ix += 1
    setfill[/allnodes/i, nhues[ix]]; ix += 1
    setfill[/swift/i, nhues[ix]]; ix += 1
    setfill[/block/i, nhues[ix]]; ix += 1
  }

  # ehues = palette(5, 80.9, 69.8)
  graph.edges.each {|edge|
    # edge[:color] = hues[1] if swords.include? "scheduler"
    if edge.snode[:shape] == 'box' and edge.dnode[:shape] == 'box'
      edge[:penwidth] = 2.0
    end
  }

  graph
end


########## RENDER #############

def write(graph)
  Mustache.template_file = 'diagram.mustache'
  view = Mustache.new
  view[:now] = Time.now.strftime("%Y.%m.%d %H:%M:%S")

  view[:title] = "Heat dependencies"
  view[:dotdata] = g2dot(graph)

  path = "heat-deps.html"
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


filename = ARGV[0]
if !File.file? filename
  raise "Not a file: #{filename}"
end
graph = nil
File.open(filename) {|file|
  graph = load_data(file)
}

graph = decorate(graph)
write(graph)
