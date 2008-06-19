#
#  PassengerPref.m
#  Passenger
#
#  Created by Eloy Duran on 5/8/08.
#  Copyright (c) 2008 Eloy Duran. All rights reserved.
#

require 'osx/cocoa'
include OSX

OSX.require_framework 'PreferencePanes'
OSX.load_bridge_support_file File.expand_path('../Security.bridgesupport', __FILE__)

require File.expand_path('../shared_passenger_behaviour', __FILE__)
require File.expand_path('../PassengerApplication', __FILE__)

class PrefPanePassenger < NSPreferencePane
  include SharedPassengerBehaviour
  
  ib_outlet :installPassengerWarning
  
  ib_outlet :authorizationView
  
  ib_outlet :applicationsTableView
  ib_outlet :applicationsController
  
  kvc_accessor :applications, :authorized
  
  def mainViewDidLoad
    @authorized = @dropping_directories = @dirty_apps = false
    
    showPassengerWarning unless passenger_installed?
    
    @authorizationView.string = OSX::KAuthorizationRightExecute
    @authorizationView.delegate = self
    @authorizationView.updateStatus self
    @authorizationView.autoupdate = true
    
    @applications = [].to_ns
    @applicationsTableView.dataSource = self
    @applicationsTableView.registerForDraggedTypes [OSX::NSFilenamesPboardType]
    
    existing_apps = PassengerApplication.existingApplications
    @applicationsController.addObjects existing_apps
    @applicationsController.selectedObjects = [existing_apps.last]
  end
  
  def remove(sender = nil)
    apps = @applicationsController.selectedObjects
    existing_apps = apps.reject { |app| app.new_app? }
    PassengerApplication.removeApplications(existing_apps) unless existing_apps.empty?
    @applicationsController.removeObjects apps
  end
  
  def showInstallPassengerHelp(sender)
    OSX::HelpHelper.openHelpPage File.expand_path('../English.lproj/PassengerPaneHelp/PassengerPaneHelp.html', __FILE__)
  end
  
  # Select application directory panel
  
  def rbSetValue_forKey(value, key)
    super
    if key == 'applications' and !value.empty? and value.last.new_app?
      browse unless @dropping_directories
      @dropping_directories = false
    end
  end
  
  def browse(sender = nil)
    panel = NSOpenPanel.openPanel
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.objc_send(
      :beginSheetForDirectory, path_for_browser,
      :file, nil,
      :types, nil,
      :modalForWindow, mainView.window,
      :modalDelegate, self,
      :didEndSelector, 'openPanelDidEnd:returnCode:contextInfo:',
      :contextInfo, nil
    )
  end
  
  def openPanelDidEnd_returnCode_contextInfo(panel, button, contextInfo)
    app = @applicationsController.selectedObjects.first
    if button == OSX::NSOKButton
      app.setValue_forKey(panel.filename, 'path')
    else
      remove if app.new_app? and !app.dirty?
    end
  end
  
  # Applications NSTableView dataSource drag and drop methods
  
  def tableView_validateDrop_proposedRow_proposedDropOperation(tableView, info, row, operation)
    return OSX::NSDragOperationNone unless @authorized
    
    files = info.draggingPasteboard.propertyListForType(OSX::NSFilenamesPboardType)
    if files.all? { |f| File.directory? f }
      @applicationsTableView.setDropRow_dropOperation(@applicationsController.content.count, OSX::NSTableViewDropAbove)
      OSX::NSDragOperationGeneric
    else
      OSX::NSDragOperationNone
    end
  end
  
  def tableView_acceptDrop_row_dropOperation(tableView, info, row, operation)
    @dropping_directories = true
    apps = info.draggingPasteboard.propertyListForType(OSX::NSFilenamesPboardType).map { |path| PassengerApplication.alloc.initWithPath(path) }
    @applicationsController.addObjects apps
    PassengerApplication.startApplications apps
  end
  
  # SFAuthorizationView: TODO this should actualy move to the SecurityHelper, but for some reason in prototyping it didn't work, try again when everything is cleaned up.
  
  def authorizationViewDidAuthorize(authorizationView = nil)
    OSX::SecurityHelper.sharedInstance.authorizationRef = @authorizationView.authorization.authorizationRef
    self.authorized = true
  end
  
  def authorizationViewDidDeauthorize(authorizationView = nil)
    OSX::SecurityHelper.sharedInstance.deauthorize
    self.authorized = false
  end
  
  def shouldUnselect
    if !@applicationsController.content.empty? and @applicationsController.selectedObjects.first.dirty?
      alert = OSX::NSAlert.alloc.init
      alert.messageText = 'This service has unsaved changes'
      alert.informativeText = 'Would you like to apply your changes before closing the Network preferences pane?'
      alert.addButtonWithTitle 'Apply'
      alert.addButtonWithTitle 'Cancel'
      alert.addButtonWithTitle 'Don’t Apply'
      alert.objc_send(
        :beginSheetModalForWindow, mainView.window,
        :modalDelegate, self,
        :didEndSelector, 'unsavedChangesAlertDidEnd:returnCode:contextInfo:',
        :contextInfo, nil
      )
      return OSX::NSUnselectLater
    end
    OSX::NSUnselectNow
  end
  
  def rbValueForKey(key)
    key == 'dirty_apps' ? (@applicationsController.content.any? { |app| app.dirty? }) : super
  end
  
  def apply(sender = nil)
    @applicationsController.content.each { |app| app.apply if app.dirty? }
  end
  
  def revert(sender = nil)
    @applicationsController.content.each { |app| app.revert if app.dirty? }
  end
  
  def restart(sender = nil)
    @applicationsController.content.each { |app| app.restart unless app.new_app? }
  end
  
  APPLY = OSX::NSAlertFirstButtonReturn
  CANCEL = OSX::NSAlertSecondButtonReturn
  DONT_APPLY = OSX::NSAlertThirdButtonReturn
  
  def unsavedChangesAlertDidEnd_returnCode_contextInfo(alert, returnCode, contextInfo)
    alert.window.orderOut(self)
    app = @applicationsController.selectedObjects.first
    case returnCode
    when CANCEL
      replyToShouldUnselect false
      return
    when APPLY
      app.apply
    when DONT_APPLY
      if app.new_app?
        remove
      else
        app.revert
      end
    end
    replyToShouldUnselect true
  end
  
  private
  
  def passenger_installed?
    `/usr/bin/gem list passenger`.include? 'passenger'
  end
  
  def path_for_browser
    @applicationsController.selectedObjects.first.nil? ? OSX.NSHomeDirectory : @applicationsController.selectedObjects.first.path
  end
  
  MODRAILS_URL = 'http://www.modrails.com'
  def showPassengerWarning
    text_field = @installPassengerWarning.subviews.first
    
    link_str = OSX::NSMutableAttributedString.alloc.initWithString(MODRAILS_URL)
    range = OSX::NSMakeRange(0, MODRAILS_URL.length)
    link_str.addAttribute_value_range OSX::NSLinkAttributeName, MODRAILS_URL, range
    link_str.addAttribute_value_range OSX::NSForegroundColorAttributeName, OSX::NSColor.blueColor, range
    link_str.addAttribute_value_range OSX::NSUnderlineStyleAttributeName, OSX::NSSingleUnderlineStyle, range
    
    text_parts = text_field.stringValue.split(MODRAILS_URL)
    
    str = OSX::NSMutableAttributedString.alloc.initWithString(text_parts.first)
    str.appendAttributedString link_str
    str.appendAttributedString OSX::NSAttributedString.alloc.initWithString(text_parts.last)
    str.addAttribute_value_range OSX::NSFontAttributeName, OSX::NSFont.systemFontOfSize(11), OSX::NSMakeRange(0, str.length)
    
    text_field.attributedStringValue = str
    
    @installPassengerWarning.hidden = false
  end
end
