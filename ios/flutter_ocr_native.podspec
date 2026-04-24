Pod::Spec.new do |s|
  s.name             = 'flutter_ocr_native'
  s.version          = '0.0.1'
  s.summary          = 'Flutter OCR plugin using native text recognition.'
  s.description      = 'Uses Apple Vision framework for on-device text recognition.'
  s.homepage         = 'https://example.com'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Author' => 'author@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.swift_version    = '5.0'
end
