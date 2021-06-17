import pyaudio
import wave
 
FORMAT = pyaudio.paInt16
CHANNELS = 1
RATE = 44100
CHUNK = 512
RECORD_SECONDS = 1
WAVE_OUTPUT_FILENAME = "recordedFile"
device_index = 2

# List and choose input sources
audio = pyaudio.PyAudio()
info = audio.get_host_api_info_by_index(0)
numdevices = info.get('deviceCount')
inputs = [False] * numdevices
while (True):
    print("Enter device id to select, and enter something random to finish")
    for i in range(0, numdevices):
        if (audio.get_device_info_by_host_api_device_index(0, i).get('maxInputChannels')) > 0:
            print("✅" if inputs[i] else "❌", "Input Device id ", i, " - ", audio.get_device_info_by_host_api_device_index(0, i).get('name'))
    try:
        index = int(input())
        if (index < 0 or index >= numdevices):
            break
        inputs[index] = True
    except ValueError:
        break


# Record audio

streams = []
for index in range(numdevices):
    if inputs[index]:
        streams.append(audio.open(format=FORMAT, channels=CHANNELS, rate=RATE, input=True, input_device_index = index, frames_per_buffer=CHUNK))

print("Recording started with ", len(streams), " devices")

frames = [ [] for _ in range(len(streams)) ]

for i in range(int(RATE / CHUNK * RECORD_SECONDS)):
    for i in range(len(streams)):
        data = streams[i].read(CHUNK)
        frames[i].append(data)

for stream in streams:
    stream.stop_stream()
    stream.close()
audio.terminate()

print ("recording finished. You can either re-record or go to the next cell to save the file")


# Save to files

for i in range(len(frames)):
    waveFile = wave.open(WAVE_OUTPUT_FILENAME+"-"+str(i)+".wav", 'wb')
    waveFile.setnchannels(CHANNELS)
    waveFile.setsampwidth(audio.get_sample_size(FORMAT))
    waveFile.setframerate(RATE)
    waveFile.writeframes(b''.join(frames[i]))
    waveFile.close()