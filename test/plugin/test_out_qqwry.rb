require 'helper'

class QQWryOutputTest < Test::Unit::TestCase
  def setup
    Fluent::Test.setup
  end

  CONFIG = %[
    qqwry_lookup_key  host
    enable_key_city   qqwry_city
    remove_tag_prefix input.
    tag               qqwry.${tag}
  ]

  def create_driver(conf=CONFIG,tag='test')
    Fluent::Test::OutputTestDriver.new(Fluent::QQWryOutput, tag).configure(conf)
  end

  def test_configure
    assert_raise(Fluent::ConfigError) {
      d = create_driver('')
    }
    assert_raise(Fluent::ConfigError) {
      d = create_driver('enable_key_cities')
    }
    d = create_driver %[
      enable_key_city   qqwry_city
      remove_tag_prefix input.
      tag               qqwry.${tag}
    ]
    assert_equal 'qqwry_city', d.instance.config['enable_key_city']

    # multiple key config
    d = create_driver %[
      qqwry_lookup_key  from.ip, to.ip
      enable_key_city   from_city, to_city
      remove_tag_prefix input.
      tag               qqwry.${tag}
    ]
    assert_equal 'from_city, to_city', d.instance.config['enable_key_city']

    # multiple key config (bad configure)
    assert_raise(Fluent::ConfigError) {
      d = create_driver %[
        qqwry_lookup_key  from.ip, to.ip
        enable_key_city   from_city
        enable_key_region from_region
        remove_tag_prefix input.
        tag               qqwry.${tag}
      ]
    }

    # invalid json structure
    assert_raise(Fluent::ConfigError) {
      d = create_driver %[
        qqwry_lookup_key  host
        <record>
          invalid_json    {"foo" => 123}
        </record>
        remove_tag_prefix input.
        tag               qqwry.${tag}
      ]
    }
    assert_raise(Fluent::ConfigError) {
      d = create_driver %[
        qqwry_lookup_key  host
        <record>
          invalid_json    {"foo" : string, "bar" : 123}
        </record>
        remove_tag_prefix input.
        tag               qqwry.${tag}
      ]
    }
  end

  def test_emit
    d1 = create_driver(CONFIG, 'input.access')
    d1.run do
      d1.emit({'host' => '66.102.3.80', 'message' => 'valid ip'})
      d1.emit({'message' => 'missing field'})
    end
    emits = d1.emits
    assert_equal 2, emits.length
    assert_equal 'qqwry.access', emits[0][0] # tag
    assert_equal 'Mountain View', emits[0][2]['qqwry_city']
    assert_equal nil, emits[1][2]['qqwry_city']
  end

  def test_emit_tag_option
    d1 = create_driver(%[
      qqwry_lookup_key  host
      <record>
        qqwry_city      ${city['host']}
      </record>
      remove_tag_prefix input.
      tag               qqwry.${tag}
    ], 'input.access')
    d1.run do
      d1.emit({'host' => '66.102.3.80', 'message' => 'valid ip'})
      d1.emit({'message' => 'missing field'})
    end
    emits = d1.emits
    assert_equal 2, emits.length
    assert_equal 'qqwry.access', emits[0][0] # tag
    assert_equal 'Mountain View', emits[0][2]['qqwry_city']
    assert_equal nil, emits[1][2]['qqwry_city']
  end

  def test_emit_tag_parts
    d1 = create_driver(%[
      qqwry_lookup_key  host
      <record>
        qqwry_city      ${city['host']}
      </record>
      tag               qqwry.${tag_parts[1]}.${tag_parts[2..3]}.${tag_parts[-1]}
    ], '0.1.2.3')
    d1.run do
      d1.emit({'host' => '66.102.3.80'})
    end
    emits = d1.emits
    assert_equal 1, emits.length
    assert_equal 'qqwry.1.2.3.3', emits[0][0] # tag
    assert_equal 'Mountain View', emits[0][2]['qqwry_city']
  end

  def test_emit_nested_attr
    d1 = create_driver(%[
      qqwry_lookup_key  host.ip
      enable_key_city   qqwry_city
      remove_tag_prefix input.
      add_tag_prefix    qqwry.
    ], 'input.access')
    d1.run do
      d1.emit({'host' => {'ip' => '66.102.3.80'}, 'message' => 'valid ip'})
      d1.emit({'message' => 'missing field'})
    end
    emits = d1.emits
    assert_equal 2, emits.length
    assert_equal 'qqwry.access', emits[0][0] # tag
    assert_equal 'Mountain View', emits[0][2]['qqwry_city']
    assert_equal nil, emits[1][2]['qqwry_city']
  end

  def test_emit_with_unknown_address
    d1 = create_driver(CONFIG, 'input.access')
    d1.run do
      # 203.0.113.1 is a test address described in RFC5737
      d1.emit({'host' => '203.0.113.1', 'message' => 'invalid ip'})
      d1.emit({'host' => '0', 'message' => 'invalid ip'})
    end
    emits = d1.emits
    assert_equal 2, emits.length
    assert_equal 'qqwry.access', emits[0][0] # tag
    assert_equal nil, emits[0][2]['qqwry_city']
    assert_equal 'qqwry.access', emits[1][0] # tag
    assert_equal nil, emits[1][2]['qqwry_city']
  end

  def test_emit_multiple_key
    d1 = create_driver(%[
      qqwry_lookup_key  from.ip, to.ip
      enable_key_city   from_city, to_city
      remove_tag_prefix input.
      add_tag_prefix    qqwry.
    ], 'input.access')
    d1.run do
      d1.emit({'from' => {'ip' => '66.102.3.80'}, 'to' => {'ip' => '125.54.95.42'}})
      d1.emit({'message' => 'missing field'})
    end
    emits = d1.emits
    assert_equal 2, emits.length
    assert_equal 'qqwry.access', emits[0][0] # tag
    assert_equal 'Mountain View', emits[0][2]['from_city']
    assert_equal 'Musashino', emits[0][2]['to_city']
    assert_equal nil, emits[1][2]['from_city']
    assert_equal nil, emits[1][2]['to_city']
  end

  def test_emit_multiple_key_multiple_record
    d1 = create_driver(%[
      qqwry_lookup_key  from.ip, to.ip
      enable_key_city   from_city, to_city
      enable_key_country_name from_country, to_country
      remove_tag_prefix input.
      add_tag_prefix    qqwry.
    ], 'input.access')
    d1.run do
      d1.emit({'from' => {'ip' => '66.102.3.80'}, 'to' => {'ip' => '125.54.95.42'}})
      d1.emit({'from' => {'ip' => '66.102.3.80'}})
      d1.emit({'message' => 'missing field'})
    end
    emits = d1.emits
    assert_equal 3, emits.length
    assert_equal 'qqwry.access', emits[0][0] # tag
    assert_equal 'Mountain View', emits[0][2]['from_city']
    assert_equal 'United States', emits[0][2]['from_country']
    assert_equal 'Musashino', emits[0][2]['to_city']
    assert_equal 'Japan', emits[0][2]['to_country']

    assert_equal 'Mountain View', emits[1][2]['from_city']
    assert_equal 'United States', emits[1][2]['from_country']
    assert_equal nil, emits[1][2]['to_city']
    assert_equal nil, emits[1][2]['to_country']

    assert_equal nil, emits[2][2]['from_city']
    assert_equal nil, emits[2][2]['from_country']
    assert_equal nil, emits[2][2]['to_city']
    assert_equal nil, emits[2][2]['to_country']
  end

  def test_emit_record_directive
    d1 = create_driver(%[
      qqwry_lookup_key  from.ip
      <record>
        from_city       ${city['from.ip']}
        from_country    ${country_name['from.ip']}
        latitude        ${latitude['from.ip']}
        longitude       ${longitude['from.ip']}
        float_concat    ${latitude['from.ip']},${longitude['from.ip']}
        float_array     [${longitude['from.ip']}, ${latitude['from.ip']}]
        float_nest      { "lat" : ${latitude['from.ip']}, "lon" : ${longitude['from.ip']}}
        string_concat   ${latitude['from.ip']},${longitude['from.ip']}
        string_array    [${city['from.ip']}, ${country_name['from.ip']}]
        string_nest     { "city" : ${city['from.ip']}, "country_name" : ${country_name['from.ip']}}
        unknown_city    ${city['unknown_key']}
        undefined       ${city['undefined']}
        broken_array1   [${longitude['from.ip']}, ${latitude['undefined']}]
        broken_array2   [${longitude['undefined']}, ${latitude['undefined']}]
      </record>
      remove_tag_prefix input.
      tag               qqwry.${tag}
    ], 'input.access')
    d1.run do
      d1.emit({'from' => {'ip' => '66.102.3.80'}})
      d1.emit({'message' => 'missing field'})
    end
    emits = d1.emits
    assert_equal 2, emits.length

    assert_equal 'qqwry.access', emits[0][0] # tag
    assert_equal 'Mountain View', emits[0][2]['from_city']
    assert_equal 'United States', emits[0][2]['from_country']
    assert_equal 37.4192008972168, emits[0][2]['latitude']
    assert_equal -122.05740356445312, emits[0][2]['longitude']
    assert_equal '37.4192008972168,-122.05740356445312', emits[0][2]['float_concat']
    assert_equal [-122.05740356445312, 37.4192008972168], emits[0][2]['float_array']
    float_nest = {"lat" => 37.4192008972168, "lon" => -122.05740356445312 }
    assert_equal float_nest, emits[0][2]['float_nest']
    assert_equal '37.4192008972168,-122.05740356445312', emits[0][2]['string_concat']
    assert_equal ["Mountain View", "United States"], emits[0][2]['string_array']
    string_nest = {"city" => "Mountain View", "country_name" => "United States"}
    assert_equal string_nest, emits[0][2]['string_nest']
    assert_equal nil, emits[0][2]['unknown_city']
    assert_equal nil, emits[0][2]['undefined']
    assert_equal [-122.05740356445312, nil], emits[0][2]['broken_array1']
    assert_equal [nil, nil], emits[0][2]['broken_array2']

    assert_equal nil, emits[1][2]['from_city']
    assert_equal nil, emits[1][2]['from_country']
    assert_equal nil, emits[1][2]['latitude']
    assert_equal nil, emits[1][2]['longitude']
    assert_equal ',', emits[1][2]['float_concat']
    assert_equal [nil, nil], emits[1][2]['float_array']
    float_nest = {"lat" => nil, "lon" => nil}
    assert_equal float_nest, emits[1][2]['float_nest']
    assert_equal ',', emits[1][2]['string_concat']
    assert_equal [nil, nil], emits[1][2]['string_array']
    string_nest = {"city" => nil, "country_name" => nil}
    assert_equal string_nest, emits[1][2]['string_nest']
    assert_equal nil, emits[1][2]['unknown_city']
    assert_equal nil, emits[1][2]['undefined']
    assert_equal [nil, nil], emits[1][2]['broken_array1']
    assert_equal [nil, nil], emits[1][2]['broken_array2']
  end

  def test_emit_record_directive_multiple_record
    d1 = create_driver(%[
      qqwry_lookup_key  from.ip, to.ip
      <record>
        from_city       ${city['from.ip']}
        to_city         ${city['to.ip']}
        from_country    ${country_name['from.ip']}
        to_country      ${country_name['to.ip']}
        string_array    [${country_name['from.ip']}, ${country_name['to.ip']}]
      </record>
      remove_tag_prefix input.
      tag               qqwry.${tag}
    ], 'input.access')
    d1.run do
      d1.emit({'from' => {'ip' => '66.102.3.80'}, 'to' => {'ip' => '125.54.95.42'}})
      d1.emit({'message' => 'missing field'})
    end
    emits = d1.emits
    assert_equal 2, emits.length

    assert_equal 'qqwry.access', emits[0][0] # tag
    assert_equal 'Mountain View', emits[0][2]['from_city']
    assert_equal 'United States', emits[0][2]['from_country']
    assert_equal 'Musashino', emits[0][2]['to_city']
    assert_equal 'Japan', emits[0][2]['to_country']
    assert_equal ['United States','Japan'], emits[0][2]['string_array']

    assert_equal nil, emits[1][2]['from_city']
    assert_equal nil, emits[1][2]['to_city']
    assert_equal nil, emits[1][2]['from_country']
    assert_equal nil, emits[1][2]['to_country']
    assert_equal [nil, nil], emits[1][2]['string_array']
  end
end
