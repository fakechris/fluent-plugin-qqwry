# fluent-plugin-qqwry

[![Gem Version](https://badge.fury.io/rb/fluent-plugin-qqwry.svg)](http://badge.fury.io/rb/fluent-plugin-qqwry)

Fluentd Output plugin to add information about geographical location of IP addresses with QQWry databases.

fluent-plugin-qqwry has bundled qqwry.dat (http://www.cz88.net)

## Dependency

before use, install dependent library as:

## Installation

install with `gem` or `fluent-gem` command as:

```bash
# for fluentd
$ gem install fluent-plugin-qqwry

# for td-agent
$ sudo /usr/lib64/fluent/ruby/bin/fluent-gem install fluent-plugin-qqwry
```

## Usage

```xml
<match access.apache>
  type qqwry

  # Specify one or more qqwry lookup field which has ip address (default: host)
  # in the case of accessing nested value, delimit keys by dot like 'host.ip'.
  qqwry_lookup_key  host

  # Specify optional qqwry database (using bundled QQWry databse by default)
  qqwry_database    '/path/to/your/qqwry.dat'

  # Set adding field with placeholder (more than one settings are required.)
  <record>
    area            ${area['host']}
    country         ${country['host']}
  </record>

  # Settings for tag
  remove_tag_prefix access.
  tag               qqwry.${tag}

  # Set log_level for fluentd-v0.10.43 or earlier (default: warn)
  log_level         info

  # Set buffering time (default: 0s)
  flush_interval    1s
</match>
```

#### Tips: how to geolocate multiple key

```xml
<match access.apache>
  type qqwry
  qqwry_lookup_key  user1_host, user2_host
  <record>
    user1_area      ${area['user1_host']}
    user2_area      ${area['user2_host']}
  </record>
  remove_tag_prefix access.
  tag               qqwry.${tag}
</match>
```

## Tutorial

#### configuration

```xml
<source>
  type forward
</source>

<match test.qqwry>
  type copy
  <store>
    type stdout
  </store>
  <store>
    type    qqwry
    qqwry_lookup_key  host
    <record>
      area  ${area['host']}
      country   ${country['host']}
    </record>
    remove_tag_prefix test.
    tag     debug.${tag}
  </store>
</match>

<match debug.**>
  type stdout
</match>
```

#### result

```bash
# forward record with Google's ip address.
$ echo '{"host":"66.102.9.80","message":"test"}' | fluent-cat test.qqwry

# check the result at stdout
$ tail /var/log/td-agent/td-agent.log
2013-08-04 16:21:32 +0900 test.qqwry: {"host":"66.102.9.80","message":"test"}
2013-08-04 16:21:32 +0900 debug.qqwry: {"host":"66.102.9.80","message":"test","area":"电信ADSL","country":"福建省厦门市海沧区"}
```

## Parameters

* `include_tag_key` (default: false)
* `tag_key`

Add original tag name into filtered record using SetTagKeyMixin.<br />
Further details are written at http://docs.fluentd.org/articles/in_exec

* `remove_tag_prefix`
* `remove_tag_suffix`
* `add_tag_prefix`
* `add_tag_suffix`

Set one or more option are required unless using `tag` option for editing tag name. (HandleTagNameMixin feature)

* `tag`

On using this option with tag placeholder like `tag qqwry.${tag}` (test code is available at [test_out_qqwry.rb](https://github.com/fakechris/fluent-plugin-qqwry/blob/master/test/plugin/test_out_qqwry.rb)), it will be overwrite after these options affected. which are remove_tag_prefix, remove_tag_suffix, add_tag_prefix and add_tag_suffix.

* `flush_interval` (default: 0 sec)

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

## Copyright

Copyright (c) 2014- Chris Song ([@fakechris](http://weibo.com/songchris))

## License

Apache License, Version 2.0
