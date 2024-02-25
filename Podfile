platform :osx, '10.15'

source 'https://github.com/CocoaPods/Specs.git'
project 'Beardie'

def commons
pod 'CocoaLumberjack', :modular_headers => true
end
def commons_swift
pod 'CocoaLumberjack/Swift', :modular_headers => true
end

target 'Beardie' do
    commons_swift
    pod 'MASPreferences', '~> 1.3'
    pod 'MASShortcut', '~> 2.4.0'
    pod 'FMDB'
    pod 'Sparkle'
    pod 'RxSSDP', :git => 'https://github.com/Stillness-2/RxSSDP'
#    pod 'RxSonosLib', :path => '../RxSonosLib'
    pod 'RxSonosLib', :git => 'https://github.com/Stillness-2/RxSonosLib'
    
    # all pods for tests should ONLY go here
    target 'BeardieTests' do
        pod 'Kiwi', '~> 3.0.0'
        # pod 'OCMock'
        pod 'VCRURLConnection', '~> 0.2.5'
    end
end
target 'beardie-nm-connector' do
  commons_swift
end

abstract_target "Commons" do
  commons
  target 'BS-Extension'
  target 'BeardieControllers' do
      pod 'MASShortcut', '~> 2.4.0'
  end
end

post_install do |installer_representation|
  installer_representation.pods_project.build_configurations.each do |config|
    config.build_settings.delete('ONLY_ACTIVE_ARCH')
  end
  installer_representation.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings.delete('MACOSX_DEPLOYMENT_TARGET')
    end
  end
end
