%% initialization
close all;
clear;
clc;

%% directory settings
root_path = fileparts(pwd);
data_path = fullfile(root_path,'data');
data_dir = dir(data_path);
data_dir = data_dir(cellfun(@(x)~contains(x,'.'),{data_dir.name}));

%% mouse settings
mouse_ids = {data_dir.name};
n_mice = numel(mouse_ids);

%% experiment settings
experiment_id = 'RandomRewards';

%% analysis parameters
baseline_period = [-2,-.5];
event_period = [-.5,1];
roi_period = [-1,1] * 2.5;
iri_cutoff = 3;

%% data parsing

% iterate through mice
for mm = 1 : n_mice
    mouse_path = fullfile(data_path,mouse_ids{mm},experiment_id);
    mouse_dir = dir(mouse_path);
    mouse_dir = mouse_dir(cellfun(@(x)~contains(x,'.'),{mouse_dir.name}));
    
    session_ids = {mouse_dir.name};
    session_days = cellfun(@(x)str2double(strrep(x,'Day','')),session_ids);
    [~,sorted_idcs] = sort(session_days);
    session_ids = session_ids(sorted_idcs);
    n_sessions = numel(session_ids);
    
    % initialize mouse counters
    mouse_dur_counter = 0;
    mouse_trial_counter = 0;
    mouse_lick_counter = 0;
    
    % iterate through sessions
    for ss = 1 : n_sessions
        progressreport(ss,n_sessions,sprintf(...
            'parsing behavioral & photometry data (mouse %i/%i)',mm,n_mice));
        session_path = fullfile(mouse_path,session_ids{ss});
        
        %% behavior
        
        % load behavior
        bhv_id = sprintf('%s_%s_eventlog.mat',...
            mouse_ids{mm},session_ids{ss});
        bhv_path = fullfile(session_path,bhv_id);
        load(bhv_path)
        
        % parse behavior
        event_labels = categorical(...
            eventlog(:,1),[5,7,0],{'lick','reward','end'});
        event_times = eventlog(:,2);
        event_idcs = (1 : numel(event_labels))';
        start_idx = find(event_labels == 'reward',1);
        end_idx = find(event_labels == 'end');
        session_dur = event_times(end_idx);
        
        valid_flags = ...
            ~isundefined(event_labels) & ...
            event_idcs >= start_idx & ...
            event_idcs < end_idx;
        n_events = sum(valid_flags);
        event_idcs = (1 : n_events)';
        event_labels = removecats(event_labels(valid_flags),'end');
        event_times = event_times(valid_flags);
        
        reward_flags = event_labels == 'reward';
        reward_idcs = find(reward_flags);
        n_rewards = sum(reward_flags);
        
        lick_flags = event_labels == 'lick';
        lick_trials = nan(n_events,1);
        
        % iterate through rewards
        for ii = 1 : n_rewards
            trial_onset = reward_idcs(ii);
            if ii < n_rewards
                trial_offset = reward_idcs(ii+1);
            else
                trial_offset = inf;
            end
            trial_flags = ...
                event_idcs > trial_onset & ...
                event_idcs < trial_offset;
            n_licks = sum(lick_flags & trial_flags);
            lick_trials(trial_flags) = 1 : n_licks;
        end
        
        lick_sessions = cumsum(~isnan(lick_trials),'omitnan');
        lick_sessions(lick_sessions == 0) = nan;
        
        solenoid_times = event_times(reward_flags);
        event_trials = sum(event_times >= event_times(reward_flags)',2);
        n_trials = max(event_trials);
        iri_nominal_prev = diff([0;solenoid_times]);
        iri_nominal_next = diff([solenoid_times;nan]);
        
        firstlick_flags = lick_trials == 1;
        firstlick_idcs = find(firstlick_flags);
        firstlick_times = event_times(firstlick_flags);
        n_firstlicks = sum(firstlick_flags);
        iri_effective_prev = nan(n_events,1);
        iri_effective_next = nan(n_events,1);
        reaction_times = nan(n_events,1);
        
        % iterate through first licks
        for ii = 1 : n_firstlicks
            trial_onset = firstlick_idcs(ii);
            firstlick_time_curr = firstlick_times(ii);
            if ii > 1
                firstlick_time_prev = firstlick_times(ii-1);
            else
                firstlick_time_prev = 0;
            end
            if ii < n_firstlicks
                trial_offset = firstlick_idcs(ii+1);
                firstlick_time_next = firstlick_times(ii+1);
            else
                trial_offset = inf;
                firstlick_time_next = inf;
            end
            trial_flags = ...
                event_idcs >= trial_onset & ...
                event_idcs < trial_offset;
            iri_effective_prev(trial_flags) = ...
                firstlick_time_curr - firstlick_time_prev;
            iri_effective_next(trial_flags) = ...
                firstlick_time_next - firstlick_time_curr;
            
            reaction_times(trial_flags) = ...
                firstlick_times(ii) - event_times(trial_onset-1);
        end
        iri_effective_prev(reward_flags) = nan;
        iri_effective_next(reward_flags) = nan;
        reaction_times(reward_flags) = nan;
        
        %% photometry
        photometry_path = fullfile(session_path,'Photometry.mat');
        load(photometry_path);
        
        % correct for nonstationary sampling frequency
        fs = 120;
        dt = 1 / fs;
        time = T(1) : dt : T(end);
        da = interp1(T,dff,time);
        
        % get event-aligned snippets of DA
        da_baseline_snippets = ...
            signal2eventsnippets(time,da,event_times,baseline_period,dt);
        da_event_snippets = ...
            signal2eventsnippets(time,da,event_times,event_period,dt);
        [da_roi_snippets,da_roi_time] = ...
            signal2eventsnippets(time,da,event_times,roi_period,dt);
        
        % preallocation
        da_response = nan(n_events,1);
        
        % iterate through events
        for ii = 1 : n_events
            
            % compute 'DA response' metric
            da_response(ii) = ...
                sum(da_event_snippets(ii,:)) - sum(da_baseline_snippets(ii,:));
        end
        
        %% combine behavioral & photometry data
        trial_subtable = table(...
            event_trials + mouse_trial_counter,...
            event_trials,...
            'variablenames',{'mouse','session'});
        
        lick_subtable = table(...
            lick_sessions + mouse_lick_counter,...
            lick_sessions,...
            lick_trials,...
            'variablenames',{'mouse','session','trial'});
        
        time_subtable = table(...
            event_times+mouse_dur_counter,...
            event_times,...
            event_times-solenoid_times(event_trials),...
            'variablenames',{'mouse','session','trial'});
        
        iri_nominal_table = table(...
            iri_nominal_prev(event_trials),...
            iri_nominal_next(event_trials),...
            'variablenames',{'previous','next'});
        
        iri_effective_table = table(...
            iri_effective_prev,...
            iri_effective_next,...
            'variablenames',{'previous','next'});

        iri_table = table(...
            iri_nominal_table,...
            iri_effective_table,...
            'variablenames',{'nominal','effective'});

        da_table = table(...
            da_roi_snippets,...
            da_baseline_snippets,...
            da_event_snippets,...
            da_response,...
            'variablenames',{'roi','pre','post','response'});
        
        session_events = table(...
            categorical(cellstr(repmat(mouse_ids{mm},n_events,1)),mouse_ids),...
            repmat(ss,n_events,1),...
            event_labels,...
            trial_subtable,...
            lick_subtable,...
            time_subtable,...
            iri_table,...
            reaction_times,...
            da_table,...
            'variablenames',{...
            'mouse',...
            'session',...
            'label',...
            'trial',...
            'lick',...
            'time',...
            'iri',...
            'rt',...
            'da'});

        % increment mouse counter
        mouse_dur_counter = mouse_dur_counter + session_dur;
        mouse_trial_counter = mouse_trial_counter + n_trials;
        mouse_lick_counter = mouse_lick_counter + ...
            lick_sessions(find(~isnan(lick_sessions),1,'last'));
        
        if ss == 1
            mouse_events = session_events;
        else
            mouse_events = [mouse_events;session_events];
        end
    end
    
    if mm == 1
        events = mouse_events;
    else
        events = [events;mouse_events];
    end
end

%% behavioral summary

% iterate through mice
for mm = 1 : n_mice
    mouse_flags = events.mouse == mouse_ids{mm};
    lick_flags = mouse_flags & events.label == 'lick';
    solenoid_flags = mouse_flags & events.label == 'reward';
    reward_flags = mouse_flags & lick_flags & events.lick.trial == 1;
    
    event_times = events.time.mouse(lick_flags);
    ili = [nan;diff(event_times)];
    
    reward_idcs = find(reward_flags);
    
    reaction_times = ...
        events.time.session(reward_idcs) - ...
        events.time.session(reward_idcs-1);
    
    trial_iri = events.iri.nominal.previous(reward_idcs-1);
    iri_flags = ...
        [trial_iri(1);trial_iri(1:end-1)] >= iri_cutoff;
    
    figure('windowstyle','docked');
    
    subplot(4,2,[1,3]);
    hold on;
    plot(events.time.trial(lick_flags),...
        events.trial.mouse(lick_flags),'.k',...
        'markersize',5);
    plot(events.time.trial(reward_idcs),...
        events.trial.mouse(reward_idcs),'or');
    title(mouse_ids{mm},'interpreter','none');
    xlabel('Time since reward (s)');
    ylabel('Trial #');
    axis tight;
    xlim([0,3]);
    
    subplot(4,2,5);
    hold on;
    set(gca,...
        'ytick',1:100:1e3);
    histogram(reaction_times,linspace(0,5,100),...
        'facecolor','k');
    histogram(reaction_times(iri_flags),linspace(0,5,100),...
        'facecolor','r');
    xlabel('Reaction time (s)');
    axis tight;
    
    subplot(4,2,7);
    plot(events.trial.mouse(reward_idcs),reaction_times,'.k');
    axis tight;
    ylim([0,quantile(reaction_times,.975)]);
    xlabel('Trial #');
    ylabel('Reaction time (s)');
    
    subplot(4,2,[2,4]);
    plot(events.trial.mouse(lick_flags),ili,'.k',...
        'markersize',5);
    xlabel('Trial #');
    ylabel('Inter-lick-interval (s)');
    axis tight;
    ylim(quantile(ili,[.01,.8]));
    
    subplot(4,2,[6,8]);
    plot(events.trial.mouse(lick_flags),...
        events.iri.nominal.previous(lick_flags),'.k',...
        'markersize',5);
    xlabel('Trial #');
    ylabel('Inter-reward-interval (s)');
    axis tight;
end
return; 
%% fetch common behavioral variables
solenoid_flags = events.label == 'reward';
lick_flags = events.label == 'lick';
reward_flags = ...
    lick_flags & ...
    events.lick.trial == 1;
iri_flags = ...
    events.iri.nominal.previous >= iri_cutoff & ...
    events.iri.nominal.next >= iri_cutoff;
% iri_flags = ...
%     events.iri.effective.previous >= iri_cutoff & ...
%     events.iri.effective.next >= iri_cutoff;
valid_flags = ...
    iri_flags;

%% plot reaction time distributions

% figure initialization
figure(...
    'windowstyle','docked',...
    'numbertitle','off',...
    'name','reaction_times',...
    'color','w');

% axes initialization
sps = gobjects(n_mice,1);
for ii = 1 : n_mice
    sps(ii) = subplot(n_mice/4,n_mice/2,ii);
end
set(sps,...
    'xlimspec','tight',...
    'ylimspec','tight',...
    'nextplot','add',...
    'linewidth',2,...
    'fontsize',12,...
    'tickdir','out');

% iterate through mice
for mm = 1 : n_mice
    mouse_flags = events.mouse == mouse_ids{mm};

    % axes labels
    title(sps(mm),mouse_ids{mm},...
        'interpreter','none');
    xlabel(sps(mm),'Reward #');
    ylabel(sps(mm),'Reaction time (s)');
    
    % iterate through sessions
    n_sessions = max(events.session(mouse_flags));
    clrs = cool(n_sessions);
    for ss = 1 : n_sessions
        session_flags = events.session == ss;
        trial_flags = ...
            mouse_flags & ...
            reward_flags & ...
            session_flags & ...
            valid_flags;
        trial_idcs = find(trial_flags);
        reaction_times = ...
            events.time.session(trial_idcs) - ...
            events.time.session(trial_idcs-1);
        reaction_times = events.rt(trial_flags);
        plot(sps(mm),...
            events.trial.mouse(trial_flags),reaction_times,'.',...
            'markersize',5,...
            'color',clrs(ss,:));
        errorbar(sps(mm),...
            nanmean(events.trial.mouse(trial_flags)),...
            nanmedian(reaction_times),...
            quantile(reaction_times,.25)-nanmedian(reaction_times),...
            quantile(reaction_times,.75)-nanmedian(reaction_times),...
            'color',clrs(ss,:),...
            'marker','o',...
            'markersize',7.5,...
            'markeredgecolor','w',...
            'markerfacecolor',clrs(ss,:),...
            'linewidth',1.5,...
            'capsize',0);
    end
    trial_flags = ...
        mouse_flags & ...
        reward_flags & ...
        valid_flags;
    trial_idcs = find(trial_flags);
    reaction_times = ...
        events.time.session(trial_idcs) - ...
        events.time.session(trial_idcs-1);
    ylim(sps(mm),quantile(reaction_times,[0,.985]));
end

%% plot previous IRI distributions (nominal)

% figure initialization
figure(...
    'windowstyle','docked',...
    'numbertitle','off',...
    'name','iri_nominal',...
    'color','w');

% axes initialization
sps = gobjects(n_mice,1);
for ii = 1 : n_mice
    sps(ii) = subplot(n_mice/4,n_mice/2,ii);
end
set(sps,...
    'xlimspec','tight',...
    'ylim',[0,60],...
    'nextplot','add',...
    'linewidth',2,...
    'fontsize',12,...
    'tickdir','out');

% iterate through mice
for mm = 1 : n_mice
    mouse_flags = events.mouse == mouse_ids{mm};

    % axes labels
    title(sps(mm),mouse_ids{mm},...
        'interpreter','none');
    xlabel(sps(mm),'Reward #');
    ylabel(sps(mm),'Nominal IRI_{t-1} (s)');

    % iterate through sessions
    n_sessions = max(events.session(mouse_flags));
    clrs = cool(n_sessions);
    for ss = 1 : n_sessions
        session_flags = events.session == ss;
        trial_flags = ...
            mouse_flags & ...
            reward_flags & ...
            session_flags & ...
            valid_flags;
        iri = events.iri.nominal.previous(trial_flags);
        plot(sps(mm),...
            events.trial.mouse(trial_flags),iri,'.',...
            'markersize',5,...
            'color',clrs(ss,:));
        errorbar(sps(mm),...
            nanmean(events.trial.mouse(trial_flags)),...
            nanmean(iri),...
            nanstd(iri),...
            'color',clrs(ss,:),...
            'marker','o',...
            'markersize',7.5,...
            'markeredgecolor','w',...
            'markerfacecolor',clrs(ss,:),...
            'linewidth',1.5,...
            'capsize',0);
    end
        
    % plot nominal mean
    plot(sps(mm),xlim(sps(mm)),[1,1]*12,'--k');
end

%% plot previous IRI distributions (effective)

% figure initialization
figure(...
    'windowstyle','docked',...
    'numbertitle','off',...
    'name','iri_effective',...
    'color','w');

% axes initialization
sps = gobjects(n_mice,1);
for ii = 1 : n_mice
    sps(ii) = subplot(n_mice/4,n_mice/2,ii);
end
set(sps,...
    'xlimspec','tight',...
    'ylim',[0,60],...
    'nextplot','add',...
    'linewidth',2,...
    'fontsize',12,...
    'tickdir','out');

% iterate through mice
for mm = 1 : n_mice
    mouse_flags = events.mouse == mouse_ids{mm};

    % axes labels
    title(sps(mm),mouse_ids{mm},...
        'interpreter','none');
    xlabel(sps(mm),'Reward #');
    ylabel(sps(mm),'Effective IRI_{t-1} (s)');
    
    % iterate through sessions
    n_sessions = max(events.session(mouse_flags));
    clrs = cool(n_sessions);
    for ss = 1 : n_sessions
        session_flags = events.session == ss;
        trial_flags = ...
            mouse_flags & ...
            reward_flags & ...
            session_flags & ...
            valid_flags;
        iri = events.iri.effective.previous(trial_flags);
        plot(sps(mm),...
            events.trial.mouse(trial_flags),iri,'.',...
            'markersize',5,...
            'color',clrs(ss,:));
        errorbar(sps(mm),...
            nanmean(events.trial.mouse(trial_flags)),...
            nanmean(iri),...
            nanstd(iri),...
            'color',clrs(ss,:),...
            'marker','o',...
            'markersize',7.5,...
            'markeredgecolor','w',...
            'markerfacecolor',clrs(ss,:),...
            'linewidth',1.5,...
            'capsize',0);
    end
        
    % plot nominal mean
    plot(sps(mm),xlim(sps(mm)),[1,1]*12,'--k');
end

%% replot fig3E (test 1)

% figure initialization
figure(...
    'windowstyle','docked',...
    'numbertitle','off',...
    'name','test_1',...
    'color','w');

% axes initialization
sps = gobjects(n_mice,1);
for ii = 1 : n_mice
    sps(ii) = subplot(n_mice/4,n_mice/2,ii);
end
set(sps,...
    'xlimspec','tight',...
    'ylimspec','tight',...
    'nextplot','add',...
    'linewidth',2,...
    'fontsize',12,...
    'tickdir','out');

% iterate through mice
for mm = 1 : n_mice
    mouse_flags = events.mouse == mouse_ids{mm};
    
    % axes labels
    title(sps(mm),mouse_ids{mm},...
        'interpreter','none');
    xlabel(sps(mm),'Reward #');
    ylabel(sps(mm),'DA response');
    
    % iterate through sessions
    n_sessions = max(events.session(mouse_flags));
    clrs = cool(n_sessions);
    for ss = 1 : n_sessions
        session_flags = events.session == ss;
        trial_flags = ...
            mouse_flags & ...
            reward_flags & ...
            session_flags;
        x = events.trial.mouse(trial_flags & valid_flags);
        X = [ones(size(x)),x];
        y = events.da.response(trial_flags & valid_flags);
        betas = robustfit(x,y);
        plot(sps(mm),...
            events.trial.mouse(trial_flags),...
            events.da.response(trial_flags),'.',...
            'markersize',7.5,...
            'color',[1,1,1]*.85);
        plot(sps(mm),...
            x,y,'.',...
            'markersize',10,...
            'color',clrs(ss,:));
        plot(sps(mm),...
            x,X*betas,'-w',...
            'linewidth',3);
        plot(sps(mm),...
            x,X*betas,'-',...
            'color',clrs(ss,:),...
            'linewidth',1.5);
    end
    trial_flags = ...
        mouse_flags & ...
        reward_flags;
    x = events.trial.mouse(trial_flags & valid_flags);
    X = [ones(size(x)),x];
    y = events.da.response(trial_flags & valid_flags);
    nan_flags = isnan(y);
    betas = robustfit(x,y);
    plot(sps(mm),...
            x,X*betas,'--k',...
        'linewidth',1);
end

%% replot fig3G (test 2)

% IRI type selection
iri_type = 'nominal';
iri_type = 'effective';

% figure initialization
figure(...
    'windowstyle','docked',...
    'numbertitle','off',...
    'name',sprintf('test_2_%s',iri_type),...
    'color','w');

% axes initialization
sps = gobjects(n_mice,1);
for ii = 1 : n_mice
    sps(ii) = subplot(n_mice/4,n_mice/2,ii);
end
set(sps,...
    'xlim',[0,60],...
    'ylimspec','tight',...
    'xscale','linear',...
    'nextplot','add',...
    'linewidth',2,...
    'fontsize',12,...
    'tickdir','out');

% iterate through mice
for mm = 1 : n_mice
    mouse_flags = events.mouse == mouse_ids{mm};

    % axes labels
    title(sps(mm),mouse_ids{mm},...
        'interpreter','none');
    xlabel(sps(mm),sprintf('Previous %s IRI (s)',iri_type));
    ylabel(sps(mm),'DA response');
    
    % iterate through sessions
    n_sessions = max(events.session(mouse_flags));
    clrs = cool(n_sessions);
    for ss = 1 : n_sessions
        session_flags = events.session == ss;
        trial_flags = ...
            mouse_flags & ...
            reward_flags & ...
            session_flags;
        x = events.iri.(iri_type).previous(trial_flags & valid_flags);
        X = [ones(size(x)),x];
        y = events.da.response(trial_flags & valid_flags);
        betas = robustfit(x,y);
        scatter(sps(mm),...
            events.iri.(iri_type).previous(trial_flags),...
            events.da.response(trial_flags),10,...
            'markerfacecolor',[1,1,1]*.75,...
            'markeredgecolor','none',...
            'markerfacealpha',.25);
        scatter(sps(mm),...
            x,y,20,...
            'markerfacecolor',clrs(ss,:),...
            'markeredgecolor','none',...
            'markerfacealpha',.25);
        [~,idcs] = sort(x);
        plot(sps(mm),...
            x(idcs),X(idcs,:)*betas,'-w',...
            'linewidth',3);
        plot(sps(mm),...
            x(idcs),X(idcs,:)*betas,'-',...
            'color',clrs(ss,:),...
            'linewidth',1.5);
    end
    trial_flags = ...
        mouse_flags & ...
        reward_flags;
    x = events.iri.(iri_type).previous(trial_flags & valid_flags);
    X = [ones(size(x)),x];
    y = events.da.response(trial_flags & valid_flags);
    nan_flags = isnan(y);
    betas = robustfit(x,y);
    [~,idcs] = sort(x);
    plot(sps(mm),...
        x(idcs),X(idcs,:)*betas,'--k',...
        'linewidth',1);
end

%% solenoid-aligned average DA

% figure initialization
figure(...
    'windowstyle','docked',...
    'numbertitle','off',...
    'name','reward_responses',...
    'color','w');

% axes initialization
sps = gobjects(n_mice,1);
for ii = 1 : n_mice
    sps(ii) = subplot(n_mice/4,n_mice/2,ii);
end
set(sps,...
    'xlim',roi_period,...
    'ylimspec','tight',...
    'xscale','linear',...
    'nextplot','add',...
    'linewidth',2,...
    'fontsize',12,...
    'tickdir','out');

% fetch relevant events & ensure no overlaps
solenoid_idcs = find(solenoid_flags);
solenoid_times = events.time.mouse(solenoid_flags);
time_mat = ...
    da_roi_time > -[inf;diff(solenoid_times)] & ...
    da_roi_time < +[diff(solenoid_times);inf];
da_mat = events.da.roi(solenoid_flags,:);
da_mat(~time_mat) = nan;

% iterate through mice
for mm = 1 : n_mice
    mouse_flags = events.mouse == mouse_ids{mm};
    
    % axes labels
    title(sps(mm),mouse_ids{mm},...
        'interpreter','none');
    xlabel(sps(mm),'Time since reward delivery (s)');
    ylabel(sps(mm),'DA (\DeltaF/F)');
    
    % iterate through sessions
    n_sessions = max(events.session(mouse_flags));
    clrs = cool(n_sessions);
    for ss = 1 : n_sessions
        session_flags = events.session == ss;
        trial_flags = ...
            mouse_flags & ...
            session_flags & ...
            valid_flags;
        da_mu = nanmean(da_mat(trial_flags(solenoid_idcs),:),1);
        da_std = nanstd(da_mat(trial_flags(solenoid_idcs),:),0,1);
        da_sem = da_std ./ sqrt(sum(time_mat(trial_flags(solenoid_idcs),:)));
        nan_flags = isnan(da_mu) | isnan(isnan(da_sem)) | da_sem == 0;
        xpatch = [da_roi_time(~nan_flags),...
            fliplr(da_roi_time(~nan_flags))];
        ypatch = [da_mu(~nan_flags)-da_sem(~nan_flags),...
            fliplr(da_mu(~nan_flags)+da_sem(~nan_flags))];
        patch(sps(mm),...
            xpatch,ypatch,clrs(ss,:),...
            'edgecolor','none',...
            'facealpha',.25);
        plot(sps(mm),...
            da_roi_time(~nan_flags),da_mu(~nan_flags),'-',...
            'color',clrs(ss,:),...
            'linewidth',1);
    end

    % plot zero line
    plot(sps(mm),[0,0],ylim(sps(mm)),'--k');
end

%% reward-aligned average DA

% figure initialization
figure(...
    'windowstyle','docked',...
    'numbertitle','off',...
    'name','firstlick_responses',...
    'color','w');

% axes initialization
sps = gobjects(n_mice,1);
for ii = 1 : n_mice
    sps(ii) = subplot(n_mice/4,n_mice/2,ii);
end
set(sps,...
    'xlim',[baseline_period(1),event_period(2)]+[-1,1]*.05*range(roi_period),...
    'ylimspec','tight',...
    'xscale','linear',...
    'nextplot','add',...
    'linewidth',2,...
    'fontsize',12,...
    'tickdir','out');

% fetch relevant events & ensure no overlaps
reward_idcs = find(reward_flags);
reward_times = events.time.mouse(reward_flags);
time_mat = ...
    da_roi_time > -[inf;diff(reward_times)] & ...
    da_roi_time < +[diff(reward_times);inf];
da_mat = events.da.roi(reward_flags,:);
da_mat(~time_mat) = nan;

% iterate through mice
for mm = 1 : n_mice
    mouse_flags = events.mouse == mouse_ids{mm};
    
    % axes labels
    title(sps(mm),mouse_ids{mm},...
        'interpreter','none');
    xlabel(sps(mm),'Time since 1^{st} rewarding lick (s)');
    ylabel(sps(mm),'DA (\DeltaF/F)');
    
    % iterate through sessions
    n_sessions = max(events.session(mouse_flags));
    clrs = cool(n_sessions);
    for ss = 1 : n_sessions
        session_flags = events.session == ss;
        trial_flags = ...
            mouse_flags & ...
            session_flags & ...
            valid_flags;
        da_mu = nanmean(da_mat(trial_flags(reward_idcs),:),1);
        da_std = nanstd(da_mat(trial_flags(reward_idcs),:),0,1);
        da_sem = da_std ./ sqrt(sum(time_mat(trial_flags(reward_idcs),:)));
        nan_flags = isnan(da_mu) | isnan(isnan(da_sem)) | da_sem == 0;
        xpatch = [da_roi_time(~nan_flags),...
            fliplr(da_roi_time(~nan_flags))];
        ypatch = [da_mu(~nan_flags)-da_sem(~nan_flags),...
            fliplr(da_mu(~nan_flags)+da_sem(~nan_flags))];
        patch(sps(mm),...
            xpatch,ypatch,clrs(ss,:),...
            'edgecolor','none',...
            'facealpha',.25);
        plot(sps(mm),...
            da_roi_time(~nan_flags),da_mu(~nan_flags),'-',...
            'color',clrs(ss,:),...
            'linewidth',1);
    end
    
    % plot response windows used to compute DA responses
    yylim = ylim(sps(mm));
    yymax = max(yylim) * 1.1;
    patch(sps(mm),...
        [baseline_period,fliplr(baseline_period)],...
        [-1,-1,1,1]*range(yylim)*.02+yymax,'w',...
        'edgecolor','k',...
        'facealpha',1,...
        'linewidth',1);
    patch(sps(mm),...
        [event_period,fliplr(event_period)],...
        [-1,-1,1,1]*range(yylim)*.02+yymax,'k',...
        'edgecolor','k',...
        'facealpha',1,...
        'linewidth',1);
    
    % plot reference lines
    plot(sps(mm),[0,0],ylim(sps(mm)),'--k');
    plot(sps(mm),[1,1]*baseline_period(2),ylim(sps(mm)),'-k',...
        'linewidth',1);
end

%% lick-aligned average DA

% lick selection
lick_idx = 2;

% figure initialization
figure(...
    'windowstyle','docked',...
    'numbertitle','off',...
    'name',sprintf('lick_%i_responses',lick_idx),...
    'color','w');

% axes initialization
sps = gobjects(n_mice,1);
for ii = 1 : n_mice
    sps(ii) = subplot(n_mice/4,n_mice/2,ii);
end
set(sps,...
    'xlim',[-1,1]*.5,...
    'ylimspec','tight',...
    'xscale','linear',...
    'nextplot','add',...
    'linewidth',2,...
    'fontsize',12,...
    'tickdir','out');

% fetch relevant events & ensure no overlaps
lick_idcs = find(lick_flags);
lick_times = events.time.mouse(lick_flags);
time_mat = ...
    da_roi_time > -[inf;diff(lick_times)] & ...
    da_roi_time < +[diff(lick_times);inf];
da_mat = events.da.roi(lick_flags,:);
da_mat(~time_mat) = nan;

% iterate through mice
for mm = 1 : n_mice
    mouse_flags = events.mouse == mouse_ids{mm};
    
    % axes labels
    title(sps(mm),mouse_ids{mm},...
        'interpreter','none');
    xlabel(sps(mm),...
        sprintf('Time since rewarding lick #%i (s)',lick_idx));
    ylabel(sps(mm),'DA (\DeltaF/F)');
    
    % iterate through sessions
    n_sessions = max(events.session(mouse_flags));
    clrs = cool(n_sessions);
    for ss = 1 : n_sessions
        session_flags = events.session == ss;
        trial_flags = ...
            mouse_flags & ...
            session_flags & ...
            events.lick.trial == lick_idx & ...
            valid_flags;
        da_mu = nanmean(da_mat(trial_flags(lick_idcs),:),1);
        da_std = nanstd(da_mat(trial_flags(lick_idcs),:),0,1);
        da_sem = da_std ./ sqrt(sum(time_mat(trial_flags(lick_idcs),:)));
        nan_flags = isnan(da_mu) | isnan(isnan(da_sem)) | da_sem == 0;
        xpatch = [da_roi_time(~nan_flags),...
            fliplr(da_roi_time(~nan_flags))];
        ypatch = [da_mu(~nan_flags)-da_sem(~nan_flags),...
            fliplr(da_mu(~nan_flags)+da_sem(~nan_flags))];
        patch(sps(mm),...
            xpatch,ypatch,clrs(ss,:),...
            'edgecolor','none',...
            'facealpha',.25);
        plot(sps(mm),...
            da_roi_time(~nan_flags),da_mu(~nan_flags),'-',...
            'color',clrs(ss,:),...
            'linewidth',1);
    end
    
    % plot zero line
    plot(sps(mm),[0,0],ylim(sps(mm)),'--k');
end

%% lick-rate

% figure initialization
figure(...
    'windowstyle','docked',...
    'numbertitle','off',...
    'name','lick_rate',...
    'color','w');

% axes initialization
sps = gobjects(n_mice,1);
for ii = 1 : n_mice
    sps(ii) = subplot(n_mice/4,n_mice/2,ii);
end
set(sps,...
    'xlim',roi_period,...
    'ylimspec','tight',...
    'xscale','linear',...
    'nextplot','add',...
    'linewidth',2,...
    'fontsize',12,...
    'tickdir','out');

% iterate through mice
for mm = 1 : n_mice
    mouse_flags = events.mouse == mouse_ids{mm};
    
    % axes labels
    title(sps(mm),mouse_ids{mm},...
        'interpreter','none');
    xlabel(sps(mm),'Time since 1^{st} rewarding lick (s)');
    ylabel(sps(mm),'Lick rate (Hz)');
    
    % iterate through sessions
    n_sessions = max(events.session(mouse_flags));
    clrs = cool(n_sessions);
    for ss = 1 : n_sessions
        session_flags = events.session == ss;
        trial_flags = ...
            mouse_flags & ...
            session_flags & ...
            valid_flags;
        
        % fetch relevant events & ensure no overlaps
        lick_counts = histcounts2(...
            events.trial.session(trial_flags & lick_flags),...
            events.time.trial(trial_flags & lick_flags) - ...
            events.rt(trial_flags & lick_flags),...
            'xbinedges',1:100+1,...
            'ybinedges',[da_roi_time,da_roi_time(end)+dt]);
        kernel = gammakernel('peakx',.1,'binwidth',dt);
        lick_rates = conv2(1,kernel.pdf,lick_counts,'same');
        
%         reward_times = events.time.mouse(trial_flags & reward_flags);
%         time_mat = ...
%             da_roi_time > -[inf;diff(reward_times)] & ...
%             da_roi_time < +[diff(reward_times);inf];
%         lick_mat(~time_mat) = nan;
        
        trial_idcs = events.trial.session(trial_flags & reward_flags);
        da_mu = nanmean(lick_rates(trial_idcs,:),1);
        da_std = nanstd(lick_rates(trial_idcs,:),0,1);
        da_sem = da_std ./ sqrt(sum(~isnan(lick_rates)));
        nan_flags = isnan(da_mu) | isnan(isnan(da_sem)) | da_sem == 0;
        xpatch = [da_roi_time(~nan_flags),...
            fliplr(da_roi_time(~nan_flags))];
        ypatch = [da_mu(~nan_flags)-da_sem(~nan_flags),...
            fliplr(da_mu(~nan_flags)+da_sem(~nan_flags))];
        patch(sps(mm),...
            xpatch,ypatch,clrs(ss,:),...
            'edgecolor','none',...
            'facealpha',.25);
        plot(sps(mm),...
            da_roi_time(~nan_flags),da_mu(~nan_flags),'-',...
            'color',clrs(ss,:),...
            'linewidth',1);
    end

    % plot zero line
    plot(sps(mm),[0,0],ylim(sps(mm)),'--k');
end