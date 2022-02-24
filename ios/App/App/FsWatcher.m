//
//  FsWatcher.m
//  Logseq
//
//  Created by Mono Wang on 2/17/R4.
//

#import <Capacitor/Capacitor.h>

CAP_PLUGIN(FsWatcher, "FsWatcher",
           CAP_PLUGIN_METHOD(watch, CAPPluginReturnCallback);
           CAP_PLUGIN_METHOD(unwatch, CAPPluginReturnPromise);
)
