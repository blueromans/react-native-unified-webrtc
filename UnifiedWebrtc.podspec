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
  s.source       = { :git => "https://github.com/yasarozyurt/react-native-unified-webrtc.git", :tag => "#{s.version}" }

  s.source_files = "ios/**/*.{h,m,mm,swift}"

  # React Native dependencies
  if respond_to?(:install_modules_dependencies, true)
    install_modules_dependencies(s)
  else
    s.dependency "React-Core"
    s.dependency "React-RCTFabric"
    s.dependency "ReactCommon"
  end

  # WebRTC dependency for streaming functionality
  s.dependency "JitsiMeetSDK", "~> 9.2.2"

  s.static_framework = true 

  # Compiler flags for C++ and Objective-C++
  s.pod_target_xcconfig = {
    "DEFINES_MODULE" => "YES",
    "CLANG_CXX_LANGUAGE_STANDARD" => "c++17",
    "HEADER_SEARCH_PATHS" => [
      "\"$(PODS_ROOT)/Headers/Private/React-Core\"",
      "\"$(PODS_ROOT)/Headers/Public/React-Core\"",
      "\"$(PODS_ROOT)/Headers/Private/ReactCommon\"",
      "\"$(PODS_ROOT)/Headers/Public/ReactCommon\"",
      "\"$(PODS_ROOT)/Headers/Private/React-RCTFabric\"",
      "\"$(PODS_ROOT)/Headers/Public/React-RCTFabric\"",
      "\"$(PODS_ROOT)/Headers/Private/RCT-Folly\"",
      "\"$(PODS_ROOT)/Headers/Public/RCT-Folly\""
    ].join(" "),
    "CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES" => "YES",
    "CLANG_WARN_DOCUMENTATION_COMMENTS" => "NO",
    "GCC_WARN_INHIBIT_ALL_WARNINGS" => "YES"
  }
  
  s.user_target_xcconfig = {
    "CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES" => "YES"
  }
end
