fftw3 = require './build/Release/fftw3.node'
stream = require 'stream'
pcm = require './pcm'
{argv} = require('optimist').usage('Usage: $0 input.wav output.wav [--time n] [--pitch n] [--step n] [--window n]').demand([2])
fs = require 'fs'
{Complex} = require './complex'

# Windowing function from paulStretch
getWindow = (i, windowSize) -> (1 - ((i - windowSize) / windowSize) ** 2) ** 1.25

class Stretcher extends stream.Transform
  constructor: (@stepBefore, @windowSize, @stepAfter) ->
    stream.Transform.call this, objectMode: true

    # Possible states are 'INIT', 'TRANSFORMING', 'NONE'
    @stretcherState = 'INIT'

    @inputBuffer = []
    @outputBuffer = (0 for [1..@windowSize])

    @forwardPlan = new fftw3.Plan @windowSize, true
    @backwardPlan = new fftw3.Plan @windowSize, false

    @timeSinceLastWindow = 0

  _transform: (number, encoding, done) ->
    switch @stretcherState
      when 'INIT'
        @inputBuffer.push number
        if @inputBuffer.length is @windowSize
          @stretcherState = 'TRANSFORMING'

        done()

      when 'TRANSFORMING'
        @timeSinceLastWindow += 1

        @inputBuffer.shift(); @inputBuffer.push number

        if @timeSinceLastWindow is @stepBefore

          # Fill up a buffer for the forward fft
          fftBuffer = []
          for el, i in @inputBuffer
            fftBuffer.push new Complex(el * getWindow(i, @windowSize), 0)
          
          # FFT forward
          @forwardPlan.execute Complex.flatten(fftBuffer), checkAgain = (data) =>

            # Now randomize phases
            data = Complex.inflate data

            for el, i in data
              data[i] = Complex.fromPolar (Math.random() * 2 * Math.PI), data[i].mag()
            
            # FFT backward. We do not need to wait for things to catch up to us.
            @backwardPlan.execute Complex.flatten(data), (ifft) =>

              ifft = Complex.inflate ifft
              
              for el, i in ifft
                @outputBuffer[i] += el.x / @windowSize * getWindow i, @windowSize

              for [1..@stepAfter]
                @push @outputBuffer.shift() + Math.random() / 1000
                @outputBuffer.push 0

              done()

          @timeSinceLastWindow = 0
        else
          done()

linearInterpolate = (before, after, ratio) -> before * (1 - ratio) + after * ratio

class Resampler extends stream.Transform
  constructor: (@factor) ->
    stream.Transform.call this, objectMode: true

    @position = 0
    @lastDataPoint = 0

  _transform: (number, encoding, done) ->
    for i in [Math.ceil(@position)...Math.ceil(@position + @factor)]
      @push linearInterpolate(@lastDataPoint, number, (i - @position) / @factor) + Math.random() / 1000

    @position += @factor
    
    @lastDataPoint = number

    done()

input = fs.createReadStream argv._[0]
output = fs.createWriteStream argv._[1]

reader = new pcm.Reader(); input.pipe reader
writer = new pcm.Writer(); writer.pipe output

time = argv.time or argv.t or 1
pitch = argv.pitch or argv.p or 1
windowSize = argv.window or argv.w or 700
stepSize = argv.step or argv.s or Math.round 100 / pitch * time

stretcher = new Stretcher stepSize, windowSize, 100
resampler = new Resampler stepSize / 100

reader.pipe(stretcher).pipe(resampler).pipe writer
