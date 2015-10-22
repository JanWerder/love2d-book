#!/usr/bin/env ruby

require 'bundler/setup'
require 'rubygems' if RUBY_VERSION < '1.9'

require 'asciidoctor-pdf'
require 'asciidoctor'
require 'asciidoctor/extensions'
require 'asciidoctor/abstract_block'

class LoveWikiMacro < Asciidoctor::Extensions::InlineMacroProcessor
  use_dsl
  named :wiki

  name_positional_attributes 'alt'

  def process parent, target, attrs
    text = Asciidoctor::Inline.new parent, :quoted, (attrs['alt'] or target), {type: :monospaced}
    target = "https://love2d.org/wiki/#{target}"
    (create_anchor parent, text.render, type: :link, target: target).render
  end
end

Asciidoctor::Extensions.register do
  block do
    named :livecode
    on_context :pass
    parse_content_as :raw
    name_positional_attributes 'name'

    process do |parent, reader, attrs|
      res = ""
      preload = (attrs.delete('preload') || '').split(',')
      name    = attrs.delete('name')
      res = %(
<div class="preload">#{(preload.map do |n| %(<img src="assets/#{name+"/"+n}" />) end).join("\n")}</div>
<canvas id="#{name}-canvas"></canvas>)
      if attrs.has_key? 'multi' then
        names = []
        reader.read.split("###").each do |t|
          spl = t.split("\n")
          next if spl == []
          file = %(tmp/#{spl[0]})
          names << file
          File.open(file, 'w') do |f|
            f.write(spl.drop(1).join("\n"))
          end
        end
        game_json = %x{node_modules/.bin/moonshine distil #{names.join(' ')}}
        res  = res + %(<script>new Punchdrunk({ "game_code": #{game_json}, "canvas": document.getElementById("#{name}-canvas") });</script>)
      else
        File.open('tmp/file.lua', 'w') do |f|
          f.write(reader.read)
        end
        game_json = %x{node_modules/.bin/moonshine distil tmp/file.lua}
        res  = res + %(<script>new Punchdrunk({ "game_code": #{game_json}, "canvas": document.getElementById("#{name}-canvas") });</script>)
      end
      create_pass_block parent, %(<div class="livecode">#{res}</div>), attrs
    end
  end

  block_macro do
    named :livecode

    parse_content_as :raw

    process do |parent, target, attrs|
      res = ""
      preload = ( attrs.delete('preload') || '').split(',')
      name = attrs.delete('name') || target
      res = %(
<div class="preload">#{(preload.map do |n| %(<img src="assets/#{target+"/"+n}" />) end).join("\n")}</div>
<canvas id="#{name}-canvas"></canvas>)
      game_json = %x{node_modules/.bin/moonshine distil -p book/code/#{target}}
      res  = res + %(<script>new Punchdrunk({ "game_code": #{game_json}, "canvas": document.getElementById("#{name}-canvas") });</script>)
      create_pass_block parent, %(<div class="livecode">#{res}</div>), attrs
    end
  end

  block_macro do
    named :code_example

    parse_content_as :raw

    process do |parent, target, attrs|
      code_dir = File.join(parent.document.base_dir, 'code', target)

      exclude = (attrs.delete('exclude') || 'lib/*').split(',')
      include = (attrs.delete('include') || '**/*.lua').split(',')

      include.map! {|pat| Dir.glob(File.join(code_dir, pat)) }
      exclude.map! {|pat| Dir.glob(File.join(code_dir, pat)) }

      res = create_open_block parent, "", attrs, content_model: :compound
      attrs['language'] ||= 'lua'
      (include.inject(&:+) - exclude.inject(&:+)).each do |file|
        block = create_listing_block res, File.read(file), attrs, subs: [:highlight, :callouts]
        block.style = "source"
        block.title = File.basename(file)
        res << block
      end
      res
    end
  end

  include_processor do
    process do |doc, reader, target, attributes|
      reader.push_include File.read(File.join(doc.base_dir, 'code', target)), target, target, 1, attributes
      reader
    end

    def handles? target
      target =~ %r(world[1-3]/.*/)
    end
  end

  inline_macro LoveWikiMacro
end

if __FILE__ == $0
  require 'asciidoctor/cli'

  ARGV << "-T"
  ARGV << "templates"
  invoker = Asciidoctor::Cli::Invoker.new ARGV
  GC.start
  invoker.invoke!
  exit invoker.code
end