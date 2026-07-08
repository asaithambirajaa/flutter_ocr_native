Pod::Spec.new do |s|
  s.name             = 'flutter_ocr_native'
  s.version          = '0.4.0'
  s.summary          = 'Flutter OCR plugin using Apple Vision framework.'
  s.description      = 'Uses Apple Vision framework for on-device text recognition on macOS.'
  s.homepage         = 'https://github.com/asaithambirajaa/flutter_ocr_native'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Author' => 'author@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'flutter_ocr_native/Sources/flutter_ocr_native/**/*.swift'
  s.dependency 'FlutterMacOS'
  s.platform         = :osx, '10.15'
  s.osx.deployment_target = '10.15'
  s.swift_version    = '5.0'
end
