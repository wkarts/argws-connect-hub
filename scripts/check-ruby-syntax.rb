# frozen_string_literal: true

roots = ARGV.empty? ? %w[app config lib db/migrate spec] : ARGV
files = roots.flat_map do |root|
  if File.directory?(root)
    Dir.glob(File.join(root, '**', '*.rb'))
  elsif File.file?(root) && File.extname(root) == '.rb'
    [root]
  else
    []
  end
end.uniq.sort

failures = []
files.each do |file|
  begin
    RubyVM::InstructionSequence.compile_file(file)
  rescue SyntaxError => e
    failures << [file, e.message]
  end
end

if failures.any?
  failures.each do |file, message|
    warn "Ruby syntax error: #{file}"
    warn message
  end
  exit 1
end

puts "Ruby syntax OK: #{files.length} files"
