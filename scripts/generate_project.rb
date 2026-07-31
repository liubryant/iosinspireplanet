require "xcodeproj"

root = File.expand_path("..", __dir__)
path = File.join(root, "InspirePlanet.xcodeproj")
project = Xcodeproj::Project.new(path)
target = project.new_target(:application, "InspirePlanet", :ios, "15.0")
target.product_name = "InspirePlanet"

app_group = project.main_group.new_group("InspirePlanet", "InspirePlanet")
swift_files = Dir.glob(File.join(root, "InspirePlanet/**/*.swift")).sort
swift_files.each do |absolute|
  relative = absolute.delete_prefix(File.join(root, "InspirePlanet/"))
  target.add_file_references([app_group.new_file(relative)])
end

["Assets.xcassets", "InspireLaunchScreen.storyboard"].each do |relative|
  target.resources_build_phase.add_file_reference(app_group.new_file(relative), true)
end
duix_resources = app_group.new_reference("Resources/duix", :group)
duix_resources.last_known_file_type = "folder"
target.resources_build_phase.add_file_reference(duix_resources, true)
app_group.new_file("Info.plist")

sdk_project_ref = project.main_group.new_file("ThirdParty/Duix/GJLocalDigitalSDK/GJLocalDigitalSDK.xcodeproj")
sdk_reference = project.root_object.project_references.find { |reference| reference[:project_ref] == sdk_project_ref }
framework_proxy = sdk_reference[:product_group].children.find { |file| file.path == "GJLocalDigitalSDK.framework" }

dependency_proxy = project.new(Xcodeproj::Project::Object::PBXContainerItemProxy)
dependency_proxy.container_portal = sdk_project_ref.uuid
dependency_proxy.proxy_type = "1"
dependency_proxy.remote_global_id_string = "A0FC3D812B282DC40069EA0E"
dependency_proxy.remote_info = "GJLocalDigitalSDK"
dependency = project.new(Xcodeproj::Project::Object::PBXTargetDependency)
dependency.target_proxy = dependency_proxy
target.dependencies << dependency

target.frameworks_build_phase.add_file_reference(framework_proxy, true)
embed = target.new_copy_files_build_phase("Embed Duix Framework")
embed.symbol_dst_subfolder_spec = :frameworks
embedded = embed.add_file_reference(framework_proxy, true)
embedded.settings = { "ATTRIBUTES" => ["CodeSignOnCopy", "RemoveHeadersOnCopy"] }

project.build_configurations.each do |config|
  config.build_settings["IPHONEOS_DEPLOYMENT_TARGET"] = "15.0"
  config.build_settings["SWIFT_VERSION"] = "5.0"
end

target.build_configurations.each do |config|
  settings = config.build_settings
  settings["PRODUCT_BUNDLE_IDENTIFIER"] = "cn.cjym.inspireplanet"
  settings["INFOPLIST_FILE"] = "InspirePlanet/Info.plist"
  settings["ASSETCATALOG_COMPILER_APPICON_NAME"] = "AppIcon"
  settings["CODE_SIGN_STYLE"] = "Automatic"
  settings["DEVELOPMENT_TEAM"] = "MF7G4UB9D9"
  settings["TARGETED_DEVICE_FAMILY"] = "1,2"
  settings["ENABLE_BITCODE"] = "NO"
  settings["LD_RUNPATH_SEARCH_PATHS"] = ["$(inherited)", "@executable_path/Frameworks"]
  settings["OTHER_LDFLAGS"] = ["$(inherited)", "-ObjC", "-lc++", "-lresolv", "-lz", "-lsqlite3", "-lbz2", "-lxml2", "-liconv", "-lc++abi"]
end

project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(target)
scheme.set_launch_target(target)
scheme.save_as(path, "InspirePlanet", true)
