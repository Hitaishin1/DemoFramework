Pod::Spec.new do |s|
s.name             = "DemoFramework"
s.version          = "0.0.3"
s.summary          = "DemoFramework push notification library for mobile apps."
s.homepage         = "https://onesignal.com"
s.license          = { :type => 'MIT', :file => 'LICENSE' }
s.author           = { "Hitaishin1" => "hitaishin.android@gmail.com"}

s.source           = { :git => "https://github.com/Hitaishin1/DemoFramework.git", :tag => s.version.to_s }

s.platform     = :ios
s.requires_arc = true

s.ios.vendored_frameworks = 'DemoFramework/Framework/Kontext.framework'
s.framework               = 'SystemConfiguration', 'UIKit', 'UserNotifications'
end

