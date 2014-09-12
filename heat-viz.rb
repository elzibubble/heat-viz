#!/usr/bin/ruby
# vim: set ts=2 sw=2:

require 'rubygems'
require './graphviz'
require 'mustache'
require 'json'
require 'fileutils'


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

def mk_graph(data, tag=nil)
  graph = Graph.from_hash(data)
  graph[:ranksep] = 2.0

  graph.nodes.each {|node|
    label = node.label
    node[:shape] = (node.key =~ /role/ and 'box' or nil)
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
    setfill[/nova/i, hsv(58, 13.7, 100)]
    setfill[/nova::/i, hsv(36, 13.7, 100)]
    setfill[/-core/i, hsv(0, 0, 95)]
  }

  graph.edges.each {|edge|
    swords = edge.src.split(/-|::/).map {|w| w.downcase }
    dwords = edge.dst.split(/-|::/).map {|w| w.downcase }
    core_rel = ((swords + ["core"]) == dwords)

    # setdst[/Nova-in-a-box/i, :color, :slateblue]
    hues = palette(5, 80.9, 69.8)
    edge[:color] = hues[1] if swords.include? "scheduler"
    edge[:color] = hues[2] if swords.include? "api"
    edge[:color] = hues[4] if swords.include? "management"
    edge[:color] = hues[3] if dwords.include? "config"
    edge[:color] = hues[0] if dwords.include? "common"
    edge[:penwidth] = 2.0 if edge[:color]
    if core_rel
      edge[:penwidth] = 4.0
      edge[:color] = :black
    end
  }
  
  graph
end


########## LOAD DATA #############

def load_data(dir)
  Hash[Dir[File.join(dir, '*.json')].map {|filename|
    File.open(filename) {|file|
      fdata = JSON::parse(file.read, :create_additions => false)
      ["role[#{fdata['name']}]",
       fdata['run_list']]
    }
  }]
end

merged = {}
by_dir = {"merged" => merged}
ARGV.each {|dir|
  if !File.directory? dir
    raise "Not a directory: #{dir}"
  end
  data = load_data(dir)
  # extract BLAH from /path/to/BLAH/roles/*.json
  tag = File.absolute_path(dir).split("/")[-2]
  by_dir[tag] = data
  merged.merge! data
}
# puts JSON::dump(merged); exit


########## RENDER #############

class GRender
  def initialize(tag)
    @tag = tag
    @graphs = {}
    @nav = []
    @nav2 = []
  end

  def add(g, name, notes = nil)
    @graphs[name] = {:graph => g,
                     :notes => notes}
  end
  def add_to_nav(g, name, label, notes = nil)
    add(g, name, notes)
    @nav << {:url => "#{name}.html", :label => label}
  end
  def add_tag(tag)
    @nav2 << {:url => "../#{tag}/simple.html", :label => tag.capitalize}
  end

  def write
    Mustache.template_file = 'chefroles.mustache'
    view = Mustache.new
    view[:now] = Time.now.strftime("%Y.%m.%d %H:%M:%S")
    view[:nav] = @nav
    view[:nav2] = @nav2

    @graphs.each_pair {|name, obj|
      view[:title] = "Chef roles - #{@tag} - #{name}"
      view[:dotdata] = g2dot(obj[:graph])
      view[:notes] = (obj[:notes] and "<p>#{obj[:notes]}</p>" or "")

      path = File.join(TOPDIR, @tag, "#{name}.html")
      File.open(path, 'w') do |f|
        f.puts view.render
      end
    }
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

def mk_graphset(data, tag, other_tags, exclude)
  tagdir = File.join(TOPDIR, tag)
  File.directory?(tagdir) or Dir.mkdir(tagdir)
  subvizjs = File.join(tagdir, VIZJS)
  File.exists?(subvizjs) or FileUtils.cp(VIZJS, subvizjs)

  grender = GRender.new(tag)
  other_tags.map {|otag| grender.add_tag(otag) }

  g0 = mk_graph(data)
  # g0.lowercut(*g0.match(*[/Nova-in-a-box/, /Nova-trivial/]))

  g1 = g0.dup
  g1.lowercut(*g1.match(*exclude.map {|i| /#{i}/i }))

  grender.add_to_nav(g1, "simple", "Simplified", "Excludes #{en_join(exclude)}.")
  grender.add_to_nav(g0, "main", "Full #{tag}")

  g0.nodes.each { |fnode|
    gf = g0.focus(fnode)
    grender.add(gf, "focus-#{fnode.node}")
  }

  grender
end

TOPDIR = "graphs"
VIZJS = "viz.js"
File.directory?(TOPDIR) or Dir.mkdir(TOPDIR)

exclude = ["Monitoring", "Basenode", "SecurityLevel-Base",
           "Devex", "ufw", "perf-target"]

by_dir.each_pair {|tag, data|
  other_tags = by_dir.keys - [tag]
  mk_graphset(data, tag, other_tags, exclude).write
}
