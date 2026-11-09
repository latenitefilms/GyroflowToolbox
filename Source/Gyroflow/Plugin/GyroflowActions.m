#import "GyroflowActions.h"
#import "GyroflowAnalysis.h"
#import "GyroflowAlertFactory.h"

@implementation GyroflowPlugIn (ToolboxActions)

- (NSString *)currentToolboxProject:(NSError **)error {
    id<FxParameterRetrievalAPI_v6> api = [self.apiManager apiForProtocol:@protocol(FxParameterRetrievalAPI_v6)];
    NSString *project = nil;
    if (!api || ![api getStringParameterValue:&project fromParameter:kCB_GyroflowProjectData] || !project.length) {
        GyroflowAnalysisError(error, @"Import a media file or Gyroflow project first."); return nil;
    }
    NSData *decoded = [[NSData alloc] initWithBase64EncodedString:project options:0];
    return decoded ? [[NSString alloc] initWithData:decoded encoding:NSUTF8StringEncoding] : project;
}

- (GyroflowParameters *)captureToolboxParameters:(NSError **)error {
    if (![self currentToolboxProject:error]) return nil;
    id<FxTimingAPI_v4> timing = [self.apiManager apiForProtocol:@protocol(FxTimingAPI_v4)];
    id<FxCustomParameterActionAPI_v4> action = [self.apiManager apiForProtocol:@protocol(FxCustomParameterActionAPI_v4)];
    CMTime time = action ? [action currentTime] : kCMTimeInvalid;
    if (!CMTIME_IS_NUMERIC(time)) [timing startTimeForEffect:&time];
    NSData *state = nil;
    if (!CMTIME_IS_NUMERIC(time)) { GyroflowAnalysisError(error, @"The clip timing is unavailable."); return nil; }
    if (![self pluginState:&state atTime:time quality:kFxQuality_HIGH error:error]) return nil;
    return [NSKeyedUnarchiver unarchivedObjectOfClass:GyroflowParameters.class fromData:state error:error];
}

- (BOOL)commitToolboxProject:(NSString *)project expectedProject:(NSString *)expected
           refreshControls:(BOOL)refresh error:(NSError **)error {
    NSString *current = [self currentToolboxProject:error];
    if (!current) return NO;
    if (![current isEqualToString:expected])
        return GyroflowAnalysisError(error, @"The project changed during this operation. Please try again with the current project.");
    id<FxParameterSettingAPI_v5> api = [self.apiManager apiForProtocol:@protocol(FxParameterSettingAPI_v5)];
    if (!api || !project.length) return GyroflowAnalysisError(error, @"The host could not save the updated project.");
    NSString *encoded = [[project dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
    if (![api setStringParameterValue:encoded toParameter:kCB_GyroflowProjectData])
        return GyroflowAnalysisError(error, @"The host could not save the updated project.");
    if (refresh) [self applyProjectDefaultsFromProject:project parameterAPI:api];
    return YES;
}

- (NSDictionary *)runToolboxRequest:(NSDictionary *)request parameters:(GyroflowParameters *)parameters error:(NSError **)error {
    NSData *data = [NSJSONSerialization dataWithJSONObject:request options:0 error:error];
    if (!data) return nil;
    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return GyroflowBridgeResult(toolboxCommand((parameters.gyroflowData ?: @"").UTF8String,
        (parameters.hostKeyframes ?: @"").UTF8String, (parameters.parameterValues ?: @"{}").UTF8String,
        json.UTF8String), error);
}

- (void)presentToolboxMessage:(NSString *)title detail:(NSString *)detail {
    NSAlert *alert = [GyroflowAlertFactory makeAlert];
    alert.messageText = title;
    alert.informativeText = detail;
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (void)performToolboxAction:(UInt32)identifier {
    if (identifier == kCB_CancelAnalysis) { [self.analysis cancel]; return; }
    id<FxCustomParameterActionAPI_v4> action = [self.apiManager apiForProtocol:@protocol(FxCustomParameterActionAPI_v4)];
    if (!action) { [self presentToolboxMessage:@"Unable to Change Settings" detail:@"The host's parameter action API is unavailable."]; return; }
    NSError *error = nil;
    NSString *analysisMode = nil;
    GyroflowParameters *parameters = nil;
    [action startAction:self];
    @try {
        if (identifier != kCB_ResetDefault) {
            parameters = [self captureToolboxParameters:&error];
            if (!parameters) return;
        }
        NSMutableDictionary *request = [NSMutableDictionary dictionary];
        BOOL refresh = NO;
        switch (identifier) {
            case kCB_AnalyseMotion: analysisMode = @"optical"; break;
            case kCB_AutoSync: analysisMode = @"synchronize"; break;
            case kCB_AnalyseLensDelay: analysisMode = @"lens_delay"; break;
            case kCB_SavePreset: {
                NSAlert *alert = [GyroflowAlertFactory makeAlert];
                alert.messageText = @"Save Preset";
                alert.informativeText = @"Save the current stabilisation settings and keyframes for other clips.";
                NSTextField *name = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 280, 24)];
                name.placeholderString = @"Preset Name";
                name.accessibilityLabel = @"Preset Name";
                alert.accessoryView = name;
                [alert addButtonWithTitle:@"Save"];
                [alert addButtonWithTitle:@"Cancel"];
                [alert.window setInitialFirstResponder:name];
                if ([alert runModal] != NSAlertFirstButtonReturn) return;
                request[@"action"] = @"save_preset";
                request[@"name"] = [name.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                break;
            }
            case kCB_RecallPreset: {
                NSDictionary *available = [self runToolboxRequest:@{@"action": @"list_presets"} parameters:parameters error:&error];
                if (!available) return;
                NSArray<NSString *> *names = [available[@"names"] sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
                if (!names.count) { [self presentToolboxMessage:@"No Saved Presets" detail:@"Use Save Preset to save the current settings."]; return; }
                NSAlert *alert = [GyroflowAlertFactory makeAlert];
                alert.messageText = @"Recall Preset";
                alert.informativeText = @"Choose the settings to apply to this clip.";
                NSPopUpButton *menu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 280, 26) pullsDown:NO];
                [menu addItemsWithTitles:names];
                menu.accessibilityLabel = @"Saved Presets";
                alert.accessoryView = menu;
                [alert addButtonWithTitle:@"Apply"];
                [alert addButtonWithTitle:@"Cancel"];
                if ([alert runModal] != NSAlertFirstButtonReturn) return;
                request[@"action"] = @"apply_preset";
                request[@"name"] = menu.titleOfSelectedItem;
                refresh = YES;
                break;
            }
            case kCB_SaveDefault: request[@"action"] = @"save_default"; break;
            case kCB_ResetDefault: request[@"action"] = @"reset_default"; break;
            case kCB_ApplyFocalLength: {
                request[@"action"] = @"focal_length";
                NSData *data = [parameters.parameterValues dataUsingEncoding:NSUTF8StringEncoding];
                NSDictionary *values = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
                request[@"focal_length"] = values[[@(kCB_FocalLengthOnly) stringValue]];
                break;
            }
            case kCB_RestoreLensProfile: request[@"action"] = @"restore_lens"; break;
            case kCB_ClearOpticalAnalysis: request[@"action"] = @"clear_optical"; break;
            default: return;
        }
        if (analysisMode) request[@"action"] = @"analysis_project";
        NSDictionary *result = [self runToolboxRequest:request parameters:parameters error:&error];
        if (!result) return;
        if ([result[@"exists"] boolValue]) {
            NSAlert *alert = [GyroflowAlertFactory makeAlert];
            alert.messageText = @"Replace Preset?";
            alert.informativeText = @"A preset with this name already exists.";
            [alert addButtonWithTitle:@"Replace"];
            [alert addButtonWithTitle:@"Cancel"];
            if ([alert runModal] != NSAlertFirstButtonReturn) return;
            request[@"replace"] = @YES;
            result = [self runToolboxRequest:request parameters:parameters error:&error];
            if (!result) return;
        }
        if (analysisMode) {
            // A custom view's host context ends with endAction:. Queue analysis while it is active.
            [self.analysis startMode:analysisMode project:result[@"project"] originalProject:parameters.gyroflowData
                parameters:parameters.parameterValues error:&error];
        } else if (result[@"project"]) {
            if ([self commitToolboxProject:result[@"project"] expectedProject:parameters.gyroflowData refreshControls:refresh error:&error]) {
                [self applyToolboxControlValues:result[@"controls"]];
            }
        } else if (identifier == kCB_SaveDefault) {
            [self presentToolboxMessage:@"Default Saved" detail:@"These stabilisation settings will apply when you import new media. Existing effects keep their current settings."];
        } else if (identifier == kCB_ResetDefault) {
            [self presentToolboxMessage:@"Default Reset" detail:@"New media will use the original stabilisation defaults."];
        }
    } @finally {
        [action endAction:self];
        if (error) [self presentToolboxMessage:analysisMode ? @"Unable to Start Analysis" : @"Unable to Complete Operation"
            detail:error.localizedDescription];
    }
}
@end
