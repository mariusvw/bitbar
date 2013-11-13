//
//  Plugin.m
//  BitBar
//
//  Created by Mat Ryer on 11/12/13.
//  Copyright (c) 2013 Bit Bar. All rights reserved.
//

#import "Plugin.h"
#import "PluginManager.h"

#define DEFAULT_TIME_INTERVAL_SECONDS 60

@implementation Plugin

- (id) init {
  if (self = [super init]) {
    self.currentLine = -1;
    self.cycleLinesIntervalSeconds = 2;
  }
  return self;
}

- (id) initWithManager:(PluginManager*)manager {
  if (self = [self init]) {
    _manager = manager;
  }
  return self;
}

- (NSStatusItem *)statusItem {
  
  if (_statusItem == nil) {
    
    // make the status item
    _statusItem = [self.manager.statusBar statusItemWithLength:NSVariableStatusItemLength];

    [_statusItem setToolTip:self.name];
    
    // build the menu
    [self rebuildMenuForStatusItem:_statusItem];
    
  }
  
  return _statusItem;
  
}

- (void) rebuildMenuForStatusItem:(NSStatusItem*)statusItem {
  
  // build the menu
  NSMenu *menu = [[NSMenu alloc] init];
  [menu setDelegate:self];
  
  if (self.isMultiline) {
    
    // put all content as an item
    NSString *line;
    for (line in self.allContentLines) {
      [menu addItemWithTitle:line action:nil keyEquivalent:@""];
    }
    
    // add the seperator
    [menu addItem:[NSMenuItem separatorItem]];
    
  }
  
  // add edit action
  NSMenuItem *prefsMenuItem = [[NSMenuItem alloc] initWithTitle:@"Preferences…" action:@selector(menuItemPreferences:) keyEquivalent:@"E"];
  [prefsMenuItem setTarget:self];
  [menu addItem:prefsMenuItem];
  
  // set the menu
  statusItem.menu = menu;
  
}

- (void)menuItemPreferences:(id)sender {
  
  NSLog(@"TODO: Open preferences");
  
}

- (NSNumber *)refreshIntervalSeconds {
  
  if (_refreshIntervalSeconds == nil) {
    
    NSArray *segments = [self.name componentsSeparatedByString:@"."];
    
    if ([segments count] < 3) {
      _refreshIntervalSeconds = [NSNumber numberWithDouble:DEFAULT_TIME_INTERVAL_SECONDS];
      return _refreshIntervalSeconds;
    }
    
    NSString *timeStr = [[segments objectAtIndex:1] lowercaseString];
    
    if ([timeStr length] < 2) {
      _refreshIntervalSeconds = [NSNumber numberWithDouble:DEFAULT_TIME_INTERVAL_SECONDS];
      return _refreshIntervalSeconds;
    }
    
    NSString *numberPart = [timeStr substringToIndex:[timeStr length]-1];
    double numericalValue = [numberPart doubleValue];
    
    if (numericalValue == 0) {
      numericalValue = DEFAULT_TIME_INTERVAL_SECONDS;
    }
    
    if ([timeStr hasSuffix:@"s"]) {
      // this is ok - but nothing to do
    } else if ([timeStr hasSuffix:@"m"]) {
      numericalValue *= 60;
    } else if ([timeStr hasSuffix:@"h"]) {
      numericalValue *= 60*60;
    } else if ([timeStr hasSuffix:@"d"]) {
      numericalValue *= 60*60*24;
    } else {
      _refreshIntervalSeconds = [NSNumber numberWithDouble:DEFAULT_TIME_INTERVAL_SECONDS];
      return _refreshIntervalSeconds;
    }
    
    _refreshIntervalSeconds = [NSNumber numberWithDouble:numericalValue];
    
  }
  
  return _refreshIntervalSeconds;
  
}

- (BOOL) refreshContentByExecutingCommand {
  
  NSTask *task = [[NSTask alloc] init];
  [task setLaunchPath:@"/bin/bash"];
  [task setArguments:[NSArray arrayWithObjects:self.path, nil]];
  
  NSPipe *stdoutPipe = [NSPipe pipe];
  [task setStandardOutput:stdoutPipe];
  
  NSPipe *stderrPipe = [NSPipe pipe];
  [task setStandardError:stderrPipe];
  
  [task launch];
  
  NSData *stdoutData = [[stdoutPipe fileHandleForReading] readDataToEndOfFile];
  NSData *stderrData = [[stderrPipe fileHandleForReading] readDataToEndOfFile];
  
  [task waitUntilExit];
  
  self.content = [[NSString alloc] initWithData:stdoutData encoding:NSUTF8StringEncoding];
  self.errorContent = [[NSString alloc] initWithData:stderrData encoding:NSUTF8StringEncoding];
  
  // failure
  if ([task terminationStatus] != 0) {
    self.lastCommandWasError = YES;
    return NO;
  }
  
  // success
  self.lastCommandWasError = NO;
  return YES;
  
}

- (BOOL) refresh {
  
  [self.lineCycleTimer invalidate];
  self.lineCycleTimer = nil;
  
  // execute command
  [self refreshContentByExecutingCommand];
  [self rebuildMenuForStatusItem:self.statusItem];
  
  // reset the current line
  self.currentLine = -1;
  
  // update the status item
  [self cycleLines];
  
  if (self.isMultiline) {
    
    // start the timer to keep cycling lines
    self.lineCycleTimer = [NSTimer scheduledTimerWithTimeInterval:self.cycleLinesIntervalSeconds target:self selector:@selector(cycleLines) userInfo:nil repeats:YES];
      
  }
  
  return YES;
  
}

- (void) cycleLines {
  
  // do nothing if the menu is open
  if (self.menuIsOpen) { return; };
  
  // update the status item
  self.currentLine++;
  
  // if we've gone too far - wrap around
  if ((NSUInteger)self.currentLine >= self.allContentLines.count) {
    self.currentLine = 0;
  }
  
  [self.statusItem setTitle:self.allContentLines[self.currentLine]];
  
}

- (void)contentHasChanged {
  _allContent = nil;
  _allContentLines = nil;
}

- (void) setContent:(NSString *)content {
  _content = content;
  [self contentHasChanged];
}
- (void) setErrorContent:(NSString *)errorContent {
  _errorContent = errorContent;
  [self contentHasChanged];
}

- (NSString *)allContent {
  if (_allContent == nil) {
    if (self.errorContent != nil) {
      _allContent = [self.content stringByAppendingString:self.errorContent];
    } else {
      _allContent = self.content;
    }
  }
  return _allContent;
}

- (NSArray *)allContentLines {
  
  if (_allContentLines == nil) {
    
    NSArray *lines = [self.allContent componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSMutableArray *cleanLines = [[NSMutableArray alloc] initWithCapacity:lines.count];
    NSString *line;
    for (line in lines) {
      
      // strip whitespace
      line = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
      
      // add the line if we have something in it
      if (line.length > 0)
        [cleanLines addObject:line];
      
    }
    
    _allContentLines = [NSArray arrayWithArray:cleanLines];
    
  }
  return _allContentLines;
  
}

- (BOOL) isMultiline {
  return [self.allContentLines count] > 1;
}

#pragma mark - NSMenuDelegate

- (void)menuWillOpen:(NSMenu *)menu {
  self.menuIsOpen = YES;
}

- (void)menuDidClose:(NSMenu *)menu {
  self.menuIsOpen = NO;
}

@end