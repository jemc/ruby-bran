# Bran

## Integrations

Bran is most useful when integrated with every part of your application that performs I/O. Because I/O is commonly abstracted away from our applications by libraries, Bran includes integrations and patches for various third-party libraries so that they can use Bran to yield control to other Fibers while waiting for I/O.

It's important to realize that some of these integrations may depend on "implementation details" of the libraries that they patch. Some libraries do not expose the public interfaces we need to integrate Bran with their I/O path, and some libraries do not even make it _clear_ which interfaces are public API and which interfaces are implementation details.

Bran integrations try to use only public interfaces wherever possible, and will otherwise try to make explicit assumptions about the interfaces they expect. Some of these assumptions can be checked at runtime when loading the integrations (attempt to "fail eagerly" in the case of poor integration). To enable this behavior, do the following before loading any Bran integration:

```ruby
require "bran/ext"

Bran::Ext.check_assumptions = true

# Load specific Bran integrations here.
```

The description of each Bran integration will also be labeled "Tested with" for known good combinations of dependent gems.

### IO, TCPServer

Use Bran with any pure-Ruby library or application that uses plain IO (such as TCPSocket and TCPServer). All blocking `read` operations on IO, `IO.select`, and `TCPServer#accept` will be patched to yield their fiber instead of blocking.

Without any other Bran integrations, this requires manually running your own concurrent fibers of execution, scoped with a thread-local fiber manager. If no fiber manager is present, the methods will function as normal (without Bran). It's easier to use with another application-wide integration (like the Rainbows integration) that manages concurrent fibers for you.

To activate the Bran integrations, simply load the corresponding files:

```ruby
require "bran/ext/io"
require "bran/ext/tcp_server"
```

### Ethon (Typhoeus)

Use Bran with any library or application that uses [Ethon][ethon] to perform HTTP requests (for example, [Typhoeus][typhoeus]). Both `Ethon::Easy#perform` and `Ethon::Multi#perform` will be patched to yield their fiber instead of blocking while waiting for the HTTP response.

Without any other Bran integrations, this requires manually running your own concurrent fibers of execution, scoped with a thread-local fiber manager. If no fiber manager is present, the methods will function as normal (without Bran). It's easier to use with another application-wide integration (like the Rainbows integration) that manages concurrent fibers for you.

To activate the Bran integration, simply load the corresponding file:

```ruby
require "bran/ext/ethon"
```

Tested with:

- `ethon 0.8.1`

### Rainbows

Use Bran with [Rainbows][rainbows], a [Unicorn][unicorn]-based and [Unicorn][unicorn]-compatible webserver from the creators of [Unicorn][unicorn].

Each worker process will allow multiple concurrent connections, accepted by the Bran adapter into a fixed-size fiber pool, with the fibers being managed by Bran. Without any other Bran integrations, you can expect this configuration to only process one request at a time, with performance on par with that of Unicorn. Using other Bran I/O integrations while handling requests will give the fibers a chance to work concurrently, increasing performance for I/O-bound loads.

To activate the Bran integration, try adding the following example configuration to your Unicorn/Rainbows config file (often called `unicorn.rb`):

```ruby
require "bran/ext/rainbows"

Rainbows! do
  use :Bran              # use the Bran adapter as the concurrency manager
  worker_connections 100 # accept 100 connections per worker (100 fibers)
end
```

Tested with:

- `rainbows 5.0.0` (`unicorn 5.0.0`, `kgio 2.10.0`)
- `rainbows 5.0.0` (`unicorn 5.0.1`, `kgio 2.10.0`)

[ethon]:    https://github.com/typhoeus/ethon
[typhoeus]: https://github.com/typhoeus/typhoeus
[rainbows]: http://rainbows.bogomips.org/
[unicorn]:  http://unicorn.bogomips.org/
