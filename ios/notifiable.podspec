Pod::Spec.new do |s|
  s.name             = 'notifiable'
  s.version          = '0.1.0'
  s.summary          = 'Notifiable Flutter plugin.'
  s.description      = 'Registers a Flutter app with Notifiable.'
  s.homepage         = 'https://notifiable.sh'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Notifiable' => 'https://notifiable.sh' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
  s.swift_version = '5.0'
end
