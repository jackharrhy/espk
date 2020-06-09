require "json"
require "uuid"

require "kemal"

struct Speaker
  include JSON::Serializable

  getter language
  getter gender
  getter voice_name

  def initialize(@language : String, @gender : String, @voice_name : String)
  end
end

struct EspeakOptions
  MIN_AMPLITUDE =   0
  MAX_AMPLITUDE = 200

  MIN_PITCH =  0
  MAX_PITCH = 99

  MIN_SPEED =  80
  MAX_SPEED = 450

  # -a <integer> | Amplitude, 0 to 200, default is 100
  getter amplitude : Int8

  # -p <integer> | Pitch adjustment, 0 to 99, default is 50
  getter pitch : Int8

  # -s <integer> | Speed in words per minute, 80 to 450, default is 175
  getter speed : Int16

  # -v <voice name> | Use voice file of this name from espeak-data/voices
  getter voice_name : String

  # -m | Interpret SSML markup, and ignore other < > tags
  getter ssml : Bool

  def initialize(valid_names, amplitude, pitch, speed, voice_name, ssml)
    raise "amplitude > #{MAX_AMPLITUDE}" if amplitude > MAX_AMPLITUDE
    raise "amplitude < #{MIN_AMPLITUDE}" if amplitude < MIN_AMPLITUDE

    raise "pitch > #{MAX_PITCH}" if pitch > MAX_PITCH
    raise "pitch < #{MIN_PITCH}" if pitch < MIN_PITCH

    raise "speed > #{MAX_SPEED}" if speed > MAX_SPEED
    raise "speed < #{MIN_SPEED}" if speed < MIN_SPEED

    raise "invalid name" unless valid_names.includes? voice_name

    @amplitude = amplitude
    @pitch = pitch
    @speed = speed
    @voice_name = voice_name
    @ssml = ssml
  end
end

def generate_speakers
  process = Process.new(
    "espeak",
    ["--voices"],
    output: Process::Redirect::Pipe
  )

  list = [] of Speaker
  map = Hash(String, Speaker).new

  lines = process.output.each_line

  mapping = lines.next

  lines.each do |line|
    data = line.split(" ").reject { |s| s.empty? }

    language = data[1]
    gender = data[2]
    voice_name = data[3]

    key = "#{language}_#{gender}_#{voice_name}"

    speaker = Speaker.new(language, gender, voice_name)

    list << speaker
    map[key] = speaker
  end

  {list, map}
end

speakers_list, speakers_map = generate_speakers()
valid_names = speakers_map.keys
speakers_map_json = speakers_map.to_json

get "/voices" do |env|
  env.response.content_type = "application/json"
  speakers_map_json
end

get "/text/:text" do |env|
  id = UUID.random
  text = env.params.url["text"]
  out_path = File.join ["./out/", "#{id}.wav"]

  begin
    amplitude = env.params.query["amplitude"]?
    amplitude = amplitude.nil? ? 100_i8 : amplitude.to_i8

    pitch = env.params.query["pitch"]?
    pitch = pitch.nil? ? 50_i8 : pitch.to_i8

    speed = env.params.query["speed"]?
    speed = speed.nil? ? 175_i16 : speed.to_i16

    voice_name = env.params.query["voice_name"]?
    voice_name = voice_name.nil? ? "en-gb_M_english" : voice_name

    ssml = env.params.query["ssml"]?
    ssml = ssml.nil? ? false : (ssml <=> "") == 0

    options = EspeakOptions.new(
      valid_names,
      amplitude,
      pitch,
      speed,
      voice_name,
      ssml,
    )

    reader, writer = IO.pipe
    writer.puts(text)
    writer.close

    args = [
      "-w",
      out_path,
      "--stdin",
      "-a",
      options.amplitude.to_s,
      "-p",
      options.pitch.to_s,
      "-s",
      options.speed.to_s,
      "-v",
      options.voice_name,
    ]

    args << "-m" if options.ssml

    process = Process.new(
      "espeak",
      args,
      input: reader,
    )

    raise Exception.new("failed!") unless process.wait.success?

    send_file env, out_path, "audio/wav"
  rescue ex
    puts "request failed: #{ex}"
    halt env, status_code: 500, response: ({error: ex.message}).to_json
  end

  if File.exists? out_path
    File.open out_path do |file|
      file.delete
    end
  end
end

{Signal::INT, Signal::TERM}.each &.trap do
  exit
end

Kemal.config.port = 3750
Kemal.run
