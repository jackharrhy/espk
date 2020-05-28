require "uuid"
require "kemal"

r = Random.new

get "/:text" do |env|
  id = UUID.new(r.random_bytes)
  text = env.params.url["text"]
  out_path = File.join ["./out/", "#{id}.wav"]

  begin
    process = Process.new("espeak", [text, "-w", out_path], output: Process::Redirect::Pipe)

    raise "failed!" unless process.wait.success?

    send_file env, out_path, "audio/wav"
  rescue ex
    puts "request failed: #{ex.message}"
  end

  if File.exists? out_path
    File.open out_path do |file|
      file.delete
    end
  end
end

Kemal.config.port = 3750
Kemal.run
