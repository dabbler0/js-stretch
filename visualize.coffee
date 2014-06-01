fftw3 = require './build/Release/fftw3.node'
fs = require 'fs'
stream = require 'stream'
pcm = require './pcm'
_ = require 'underscore'
{Complex} = require './complex'

google.load 'visualization', '1'

google.setOnLoadCallback ->
  getPowerTable = (options) ->
    options = _.extend {
      windowSize: 8000
      stepSize: 1000
      nframes: 5
      success: ->
    }, options
    
    unless options.stream?
      throw new Error 'Missing "stream" option.'

    powerTable = []
    
    plan = new fftw3.Plan options.windowSize, true
    buffer = []
    timeSinceLastFrame = 0
    powerTableIndex = 0

    options.stream.on 'data', (number) ->

      if powerTableIndex < options.nframes
        buffer.push number

        if buffer.length > options.windowSize
          buffer.shift()

        timeSinceLastFrame += 1

        if timeSinceLastFrame >= options.stepSize and buffer.length is options.windowSize
          timeSinceLastFrame = 0
          do (powerTableIndex) ->
            fftBuffer = (new Complex(el, 0) for el in buffer)
            plan.execute Complex.flatten(fftBuffer), checkAgain = (data) ->
              data = Complex.inflate data

              powerSeries = (el.mag() for el, i in data)

              powerTable[powerTableIndex] = powerSeries

              if powerTableIndex is options.nframes - 1
                options.success powerTable

          powerTableIndex += 1

  input = fs.createReadStream 'audio.wav'

  reader = new pcm.Reader(); input.pipe reader

  FRAMES = 10
  WINDOW = 1000

  getPowerTable
    stream: reader
    nframes: FRAMES
    windowSize: WINDOW
    stepSize: WINDOW / 4
    success: (powers) ->
      # We've obtained the STFT frames for the audio. Now set things up properly:
      data = new google.visualization.DataTable()

      for i in [1..WINDOW]
        data.addColumn 'number', 'col' + i

      data.addRows FRAMES

      for frame, i in powers
        for power, j in frame
          data.setValue i, j, power / (WINDOW * 100)

      surfacePlot = new greg.ross.visualization.SurfacePlot document.getElementById 'surfacePlotDiv'

      surfacePlot.draw data, {
        xPos: 50
        yPos: 0
        width: 500
        height: 500
        colourGradient: [
          {red: 0, green: 0, blue: 255}
          {red: 0, green: 255, blue: 255}
          {red: 0, green: 255, blue: 0}
          {red: 255, green: 255, blue: 0}
          {red: 255, green:0, blue: 0}
        ]
        fillPolygons: true
        xTitle: 'X'
        yTitle: 'Y'
        zTitle: 'Z'
        restrictXRotation: false
      }
