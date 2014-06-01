stream = require 'stream'

exports.Reader = class Reader extends stream.Transform
  constructor: ->
    stream.Transform.call this, objectMode: true

  _transform: (chunk, encoding, done) ->
    for byte, offset in chunk by 2
      @push chunk.readInt16LE(offset) + Math.random() / 1000

    done()

exports.Writer = class Writer extends stream.Transform
  constructor: ->
    @intBuffer = new Buffer 5000
    @position = 0
    stream.Transform.call this, objectMode: true

    headerBuffer = headerBuffer = new Buffer 44
    headerBuffer.write 'RIFF', 0
    headerBuffer.writeUInt32LE 4294967295, 4
    headerBuffer.write 'WAVEfmt ', 8
    headerBuffer.writeUInt32LE 16, 16
    headerBuffer.writeUInt16LE 1, 20
    headerBuffer.writeUInt16LE 1, 22
    headerBuffer.writeUInt32LE 8000, 24
    headerBuffer.writeUInt32LE 8000 * 2, 28
    headerBuffer.writeUInt16LE 2, 32
    headerBuffer.writeUInt16LE 16, 34
    headerBuffer.write 'data', 36
    headerBuffer.writeUInt32LE 4294967295, 40

    @push headerBuffer

  _transform: (num, encoding, done) ->
    if num > 32767 then num = 32767
    if num < -32767 then num = -32767

    @intBuffer.writeInt16LE Math.round(num), @position
    @position += 2
    
    if @position is 5000
      console.log 'writing buffer'
      @push @intBuffer
      @intBuffer = new Buffer 5000
      @position = 0
    
    done()
