require 'fluent/mixin/rewrite_tag_name'

class Fluent::QQWryOutput < Fluent::BufferedOutput
  Fluent::Plugin.register_output('qqwry', self)

  REGEXP_JSON = /(^[\[\{].+[\]\}]$|^[\d\.\-]+$)/
  REGEXP_PLACEHOLDER_SINGLE = /^\$\{(?<qqwry_key>-?[^\[]+)\['(?<record_key>-?[^']+)'\]\}$/
  REGEXP_PLACEHOLDER_SCAN = /(\$\{[^\}]+?\})/
  QQWRY_KEYS = %w(area country)

  config_param :qqwry_database, :string, :default => File.dirname(__FILE__) + '/../../../data/qqwry.dat'
  config_param :qqwry_lookup_key, :string, :default => 'host'
  config_param :tag, :string, :default => nil

  include Fluent::HandleTagNameMixin
  include Fluent::SetTagKeyMixin
  config_set_default :include_tag_key, false

  include Fluent::Mixin::RewriteTagName
  config_param :hostname_command, :string, :default => 'hostname'

  config_param :flush_interval, :time, :default => 0
  config_param :log_level, :string, :default => 'warn'

  # Define `log` method for v0.10.42 or earlier
  unless method_defined?(:log)
    define_method("log") { $log }
  end

  def initialize
    require 'qqwry'
    require 'yajl'

    super
  end

  def configure(conf)
    super

    @map = {}
    @qqwry_lookup_key = @qqwry_lookup_key.split(/\s*,\s*/)

    # enable_key_* format (legacy format)
    conf.keys.select{|k| k =~ /^enable_key_/}.each do |key|
      qqwry_key = key.sub('enable_key_','')
      raise Fluent::ConfigError, "qqwry: unsupported key #{qqwry_key}" unless QQWRY_KEYS.include?(qqwry_key)
      @qqwry_lookup_key.zip(conf[key].split(/\s*,\s*/)).each do |lookup_field,record_key|
        if record_key.nil?
          raise Fluent::ConfigError, "qqwry: missing value found at '#{key} #{lookup_field}'"
        end
        @map.store(record_key, "${#{qqwry_key}['#{lookup_field}']}")
      end
    end
    if conf.keys.select{|k| k =~ /^enable_key_/}.size > 0
      log.warn "qqwry: 'enable_key_*' config format is obsoleted. use <record></record> directive for now."
      log.warn "qqwry: for further details referable to https://github.com/fakechris/fluent-plugin-qqwry"
    end

    # <record></record> directive
    conf.elements.select { |element| element.name == 'record' }.each { |element|
      element.each_pair { |k, v|
        element.has_key?(k) # to suppress unread configuration warning
        @map[k] = v
        validate_json = Proc.new {
          begin
            dummy_text = Yajl::Encoder.encode('dummy_text')
            Yajl::Parser.parse(v.gsub(REGEXP_PLACEHOLDER_SCAN, dummy_text))
          rescue Yajl::ParseError => e
            raise Fluent::ConfigError, "qqwry: failed to parse '#{v}' as json."
          end
        }
        validate_json.call if v.match(REGEXP_JSON)
      }
    }
    @placeholder_keys = @map.values.join.scan(REGEXP_PLACEHOLDER_SCAN).map{ |placeholder| placeholder[0] }.uniq
    @placeholder_keys.each do |key|
      qqwry_key = key.match(REGEXP_PLACEHOLDER_SINGLE)[:qqwry_key]
      raise Fluent::ConfigError, "qqwry: unsupported key #{qqwry_key}" unless QQWRY_KEYS.include?(qqwry_key)
    end
    @placeholder_expander = PlaceholderExpander.new

    if ( !@tag && !@remove_tag_prefix && !@remove_tag_suffix && !@add_tag_prefix && !@add_tag_suffix )
      raise Fluent::ConfigError, "qqwry: required at least one option of 'tag', 'remove_tag_prefix', 'remove_tag_suffix', 'add_tag_prefix', 'add_tag_suffix'."
    end

    @qqwry = QQWry::Database.new(@qqwry_database)
  end

  def start
    super
  end

  def format(tag, time, record)
    [tag, time, record].to_msgpack
  end

  def shutdown
    super
  end

  def write(chunk)
    chunk.msgpack_each do |tag, time, record|
      Fluent::Engine.emit(tag, time, add_qqwry_field(record))
    end
  end

  private
  def add_qqwry_field(record)
    placeholder = create_placeholder(geolocate(get_address(record)))
    @map.each do |record_key, value|
      if value.match(REGEXP_PLACEHOLDER_SINGLE)
        rewrited = placeholder[value]
      elsif value.match(REGEXP_JSON)
        rewrited = value.gsub(REGEXP_PLACEHOLDER_SCAN) {|match|
          Yajl::Encoder.encode(placeholder[match])
        }
        rewrited = parse_json(rewrited)
      else
        rewrited = value.gsub(REGEXP_PLACEHOLDER_SCAN, placeholder)
      end
      record.store(record_key, rewrited)
    end
    return record
  end

  def parse_json(message)
    begin
      return Yajl::Parser.parse(message)
    rescue Yajl::ParseError => e
      log.info "qqwry: failed to parse '#{message}' as json.", :error_class => e.class, :error => e.message
      return nil
    end
  end

  def get_address(record)
    address = {}
    @qqwry_lookup_key.each do |field|
      key = field.split('.')
      obj = record
      key.each {|k|
        break obj = nil if not obj.has_key?(k)
        obj = obj[k]
      }
      address.store(field, obj)
    end
    return address
  end

  def geolocate(addresses)
    geodata = {}
    addresses.each do |field, ip|
      geo = ip.nil? ? nil : @qqwry.query(ip)
      geodata.store(field, geo)
    end
    return geodata
  end

  def create_placeholder(geodata)
    placeholder = {}
    @placeholder_keys.each do |placeholder_key|
      position = placeholder_key.match(REGEXP_PLACEHOLDER_SINGLE)
      next if position.nil? or geodata[position[:record_key]].nil?
      placeholder.store(placeholder_key, geodata[position[:record_key]].send(position[:qqwry_key].to_sym))
    end
    return placeholder
  end
end
