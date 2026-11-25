platform :osx, '13.0'

source 'https://github.com/CocoaPods/Specs.git'
project 'Beardie'

target 'Beardie' do
    pod 'MASShortcut', '~> 2.4.0'
    pod 'RxSSDP', :git => 'https://github.com/Stillness-2/RxSSDP'
#    pod 'RxSonosLib', :path => '../RxSonosLib'
    pod 'RxSonosLib', :git => 'https://github.com/Stillness-2/RxSonosLib'
end
target 'BeardieControllers' do
  pod 'MASShortcut', '~> 2.4.0'
end

# Xcode 27 no longer supports deployment targets below macOS 12.0.
# Keep all pod targets aligned with the application's minimum (macOS 13.0).
post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '13.0'
    end
  end
end
