fftw3 = require '../lib/fftw3/build/Release/fftw3.node'
complex = require '../lib/fftw3/complex'
require 'colors'

TEST_TIMES = 10

test = (frequency, windowLength) ->

  tone = []
  for x in [1..windowLength]
    tone.push Math.sin 2 * Math.PI * frequency * x / windowLength
    tone.push 0

  forwardPlan = new fftw3.Plan windowLength, true
  backwardPlan = new fftw3.Plan windowLength, false

  forwardPlan.execute tone, (x) ->
    result = complex.inflate x
    dB = complex.dB result
    
    max = 0
    peak = 0
    for element, i in dB
      if element > max
        max = element
        peak = i
    
    if peak is frequency or peak is windowLength - frequency
      console.log "#{"PASSED".green}: Frequency peak is in the proper position (frequency=peak=#{frequency}, windowLength=#{windowLength})"
    else
      console.log "#{"FAILED".red}: Frequency peak is in the wrong position (frequency=#{frequency}, peak=#{peak}, windowLength=#{windowLength})"

    backwardPlan.execute x, (newTone) ->
      for element, i in tone
        newTone[i] /= windowLength
        if Math.abs(element - newTone[i]) > 0.001
          console.log "#{"FAILED".red}: Failed unity test (frequency=#{frequency}, i=#{i}, windowLength=#{windowLength})"
          break
      console.log "#{"PASSED".green}: Passed unity test (frequency=#{frequency}, windowLength=#{windowLength})"

for [1..TEST_TIMES]
  windowLength = Math.floor Math.random() * 5000
  frequency = Math.floor Math.random() * windowLength

  test frequency, windowLength
