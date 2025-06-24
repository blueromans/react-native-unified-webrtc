require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

# It's good practice to define this, or use a static string directly.
# This would typically be inherited from the main app's Podfile in a React Native project.
def min_ios_version_supported
  package["iosMinVersion"] || "12.0" # Fallback to "12.0" if not in package.json
end

Pod::Spec.new do |s|
  s.name         = "UnifiedWebrtc"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = package["author"]

  s.platforms    = { :ios => min_ios_version_supported }
  s.source       = { :git => "https://github.com/blueromans/react-native-unified-webrtc.git", :tag => "#{s.version}" }

  s.source_files = "ios/**/*.{h,m,mm,cpp}"
  # If you have headers that should not be public, list them here.
  # For example, if some .h files are implementation details.
  # s.private_header_files = "ios/Private/**/*.h" 

  s.dependency "JitsiWebRTC", "~> 124.0" # Use Jitsi's WebRTC library to match Android
  s.dependency "React-Core"
  s.dependency "React-RCTFabric" # For Fabric components like RCTViewComponentView
  s.dependency "ReactCommon" # Often needed with Fabric
  s.dependency "RCT-Folly" # React Native's Folly

  s.static_framework = true 

  s.frameworks = 'AVFoundation', 'AudioToolbox', 'CoreGraphics', 'CoreMedia', 'GLKit', 'VideoToolbox', 'MetalKit'
  s.libraries = 'c', 'c++', 'sqlite3'

  s.xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++20', # Matched to build logs
    # 'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) WEBRTC_IOS=1', # Example
  }
  
  s.pod_target_xcconfig = {
    'CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++20', # Ensure consistency
    'CLANG_CXX_LIBRARY' => 'libc++',
    # The following flag is important for the New Architecture (Fabric/TurboModules)
    # It ensures that the codegen files are compiled correctly.
    # From the build log, it seems like you are using the New Architecture.
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) RN_FABRIC_ENABLED=1',
  }

  # If using React Native's New Architecture (TurboModules/Fabric),
  # you might need to set this flag. The build log suggests Codegen is in use.
  s.compiler_flags = '-DRN_FABRIC_ENABLED=1'
end
