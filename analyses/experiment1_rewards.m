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

%% acquisition settings
fs = 120;
dt = 1 / fs;

%% smoothing kernels
lickrate_kernel = gammakernel('peakx',.15,'binwidth',dt);
% lickrate_kernel = expkernel('mu',1/3,'binwidth',dt);

%% analysis parameters
roi_period = [-4,8];
baseline_period = [-2,-.5];
reward_period = [-.5,1];
lick_period = roi_period + lickrate_kernel.paddx;

%% selection criteria
iri_cutoff = 3;

%% data parsing

% iterate through mice
for mm = 1 : n_mice
    
    % parse mouse directory
    mouse_path = fullfile(data_path,mouse_ids{mm},experiment_id);
    mouse_dir = dir(mouse_path);
    mouse_dir = mouse_dir(cellfun(@(x)~contains(x,'.'),{mouse_dir.name}));
    
    % parse session directory
    session_ids = {mouse_dir.name};
    session_days = cellfun(@(x)str2double(strrep(x,'Day','')),session_ids);
    [~,sorted_idcs] = sort(session_days);
    session_ids = session_ids(sorted_idcs);
    n_sessions = numel(session_ids);
    
    % initialize mouse counters
    mouse_reward_counter = 0;
    
    % mouse-specific session selection
    if mm == 3
%         n_sessions = 7;
    end
    
    % iterate through sessions
    for ss = 1 : n_sessions
        progressreport(ss,n_sessions,sprintf(...
            'parsing behavioral & photometry data (mouse %i/%i)',mm,n_mice));
        session_path = fullfile(mouse_path,session_ids{ss});
        
        %% load behavioral data
        bhv_id = sprintf('%s_%s_eventlog.mat',...
            mouse_ids{mm},session_ids{ss});
        bhv_path = fullfile(session_path,bhv_id);
        load(bhv_path)
        
        %% parse events
        event_labels = categorical(...
            eventlog(:,1),[5,7,0],{'lick','reward','end'});
        event_times = eventlog(:,2);
        event_idcs = (1 : numel(event_labels))';
        start_idx = find(event_labels == 'reward',1);
        end_idx = find(event_labels == 'end');
        session_dur = event_times(end_idx);

        %% event selection
        valid_flags = ...
            ~isundefined(event_labels) & ...
            event_idcs >= start_idx & ...
            event_idcs < end_idx;
        n_events = sum(valid_flags);
        event_idcs = (1 : n_events)';
        event_labels = removecats(event_labels(valid_flags),'end');
        event_times = event_times(valid_flags);
        
        %% parse rewards
        reward_flags = event_labels == 'reward';
        reward_events = find(reward_flags);
        reward_times = event_times(reward_flags);
        n_rewards = sum(reward_flags);
        reward_idcs = (1 : n_rewards)';
        
        %% parse first licks after reward delivery
        lick_flags = event_labels == 'lick';
        firstlick_flags = [false; diff(lick_flags) == 1];
        firstlick_events = event_idcs(firstlick_flags);
        firstlick_times = event_times(firstlick_flags);
        firstlick_idcs = sum(reward_times > firstlick_times',2) + 1;
        firstlick_times = firstlick_times(firstlick_idcs);
        n_firstlicks = sum(firstlick_flags);
        
        %% parse reward magnitude
        % not sure about this one... we should probably just remove rewards
        % that were not followed by licks, and then use the magnitude to
        % select (or compare) (?)
        
        % preallocation
        reward_magnitudes = nan(n_rewards,1);
        
        % iterate through rewards
        for ii = 1 : n_rewards
            reward_event = reward_events(ii);
            event_idx = reward_event - 1;
            reward_magnitude = 1;
            while event_idx > 0 && reward_flags(event_idx)
                reward_magnitude = reward_magnitude + 1;
                event_idx = event_idx - 1;
            end
            reward_magnitudes(ii) = reward_magnitude;
        end
        
        %% compute IRI (nominal & actual)
        iri_nominal = diff([0;reward_times]);
        iri_actual = diff([0;event_times(firstlick_flags)]);
        iri_actual = iri_actual(firstlick_idcs);
        
        %% parse reaction time
        reaction_times = firstlick_times - reward_times;
        
        %% load photometry data
        photometry_path = fullfile(session_path,'Photometry.mat');
        load(photometry_path);
        
        %% parse licks
        lick_times = event_times(lick_flags);
        lick_edges = event_times(1) : dt : event_times(end);
        lick_counts = histcounts(lick_times,lick_edges);
        
        % get lick-aligned snippets of lick counts
        [lick_reward_snippets,lick_roi_time] = signal2eventsnippets(...
            lick_edges(1:end-1),lick_counts,reward_times,lick_period,dt);
        [lick_firstlick_snippets,lick_roi_time] = signal2eventsnippets(...
            lick_edges(1:end-1),lick_counts,firstlick_times,lick_period,dt);
        
        % nanify (maybe this should be moved inside??? the snippet fun???)
        time_mat = ...
            lick_roi_time > -[inf;diff(reward_times)] & ...
            lick_roi_time < +[diff(reward_times);inf];
        lick_reward_snippets(~time_mat) = nan;
        time_mat = ...
            lick_roi_time > -[inf;diff(firstlick_times)] & ...
            lick_roi_time < +[diff(firstlick_times);inf];
        lick_firstlick_snippets(~time_mat) = nan;
        
        %% parse photometry data
        
        % correct for nonstationary sampling frequency
        time = T(1) : dt : T(end);
        da = interp1(T,dff,time);
        
        % get event-aligned snippets of DA
        [da_baseline_snippets,da_baseline_time] = signal2eventsnippets(...
            time,da,firstlick_times,baseline_period,dt);
        [da_reward_snippets,da_reward_time] = signal2eventsnippets(...
            time,da,firstlick_times,reward_period,dt);
        [da_roi_snippets,da_roi_time] = signal2eventsnippets(...
            time,da,reward_times,roi_period,dt);
        
        % nanify (maybe this should be moved inside??? the snippet fun???)
        %         time_mat = ...
        %             da_roi_time > -[inf;reaction_times(1:end-1)] & ...
        %             da_roi_time < reaction_times;
        %         da_roi_snippets(~time_mat) = nan;
        
        % preallocation
        da_response = nan(n_rewards,1);
        
        % iterate through rewards
        for ii = 1 : n_rewards
            
            % compute 'DA response' metric
            da_response(ii) = ...
                sum(da_reward_snippets(ii,:)) - sum(da_baseline_snippets(ii,:));
        end
        
        %% organize session data into tables
        
        % construct trial table
        index_table = table(...
            reward_idcs + mouse_reward_counter,...
            reward_idcs,...
            'variablenames',{...
            'mouse',...
            'session',...
            });
        
        % construct time table
        time_table = table(...
            reward_times,...
            firstlick_times,...
            'variablenames',{...
            'delivery',...
            'collection',...
            });
        
        % construct reward table
        reward_table = table(...
            index_table,...
            time_table,...
            'variablenames',{...
            'index',...
            'time',...
            });
        
        % construct IRI table
        iri_table = table(...
            iri_nominal,...
            iri_actual,...
            'variablenames',{...
            'nominal',...
            'actual',...
            });
        
        % construct lick table
        lick_table = table(...
            lick_reward_snippets,...
            lick_firstlick_snippets,...
            'variablenames',{'delivery','collection'});
        
        % construct DA table
        da_table = table(...
            da_roi_snippets,...
            da_baseline_snippets,...
            da_reward_snippets,...
            da_response,...
            'variablenames',{'roi','baseline','reward','response'});
        
        % concatenate into a session table
        session_data = table(...
            categorical(cellstr(repmat(mouse_ids{mm},n_rewards,1)),mouse_ids),...
            repmat(ss,n_rewards,1),...
            reward_table,...
            iri_table,...
            reaction_times,...
            lick_table,...
            da_table,...
            'variablenames',{...
            'mouse',...
            'session',...
            'reward'...
            'iri',...
            'rt',...
            'licks',...
            'da',...
            });
        
        % increment mouse counters
        mouse_reward_counter = mouse_reward_counter + n_rewards;
        
        % append to the current mouse's table
        if ss == 1
            mouse_data = session_data;
        else
            mouse_data = [mouse_data; session_data];
        end
    end
    
    % append to the final data table
    if mm == 1
        data = mouse_data;
    else
        data = [data;mouse_data];
    end
end

%% reward selection criteria
iri_flags = ...
    data.iri.nominal >= iri_cutoff & ...
    [data.iri.nominal(2:end); nan] >= iri_cutoff;
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
    mouse_flags = data.mouse == mouse_ids{mm};
    
    % axes labels
    title(sps(mm),mouse_ids{mm},...
        'interpreter','none');
    xlabel(sps(mm),'Reward #');
    ylabel(sps(mm),'Reaction time (s)');
    
    % iterate through sessions
    n_sessions = max(data.session(mouse_flags));
    clrs = cool(n_sessions);
    for ss = 1 : n_sessions
        session_flags = data.session == ss;
        reward_flags = ...
            mouse_flags & ...
            session_flags & ...
            valid_flags;
        reaction_times = data.rt(reward_flags);
        plot(sps(mm),...
            data.reward.index.mouse(reward_flags),reaction_times,'.',...
            'markersize',7.5,...
            'color',clrs(ss,:));
        errorbar(sps(mm),...
            nanmean(data.reward.index.mouse(reward_flags)),...
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
    reward_flags = ...
        mouse_flags & ...
        valid_flags;
    reaction_times = data.rt(reward_flags);
    ylim(sps(mm),quantile(reaction_times,[0,.95]));
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
    mouse_flags = data.mouse == mouse_ids{mm};
    
    % axes labels
    title(sps(mm),mouse_ids{mm},...
        'interpreter','none');
    xlabel(sps(mm),'Reward #');
    ylabel(sps(mm),'Previous nominal IRI (s)');
    
    % iterate through sessions
    n_sessions = max(data.session(mouse_flags));
    clrs = cool(n_sessions);
    for ss = 1 : n_sessions
        session_flags = data.session == ss;
        reward_flags = ...
            mouse_flags & ...
            session_flags & ...
            valid_flags;
        iri = data.iri.nominal(reward_flags);
        plot(sps(mm),...
            data.reward.index.mouse(reward_flags),iri,'.',...
            'markersize',5,...
            'color',clrs(ss,:));
        errorbar(sps(mm),...
            nanmean(data.reward.index.mouse(reward_flags)),...
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

%% plot previous IRI distributions (actual)

% figure initialization
figure(...
    'windowstyle','docked',...
    'numbertitle','off',...
    'name','iri_actual',...
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
    mouse_flags = data.mouse == mouse_ids{mm};
    
    % axes labels
    title(sps(mm),mouse_ids{mm},...
        'interpreter','none');
    xlabel(sps(mm),'Reward #');
    ylabel(sps(mm),'Previous actual IRI (s)');
    
    % iterate through sessions
    n_sessions = max(data.session(mouse_flags));
    clrs = cool(n_sessions);
    for ss = 1 : n_sessions
        session_flags = data.session == ss;
        reward_flags = ...
            mouse_flags & ...
            session_flags & ...
            valid_flags;
        iri = data.iri.actual(reward_flags);
        plot(sps(mm),...
            data.reward.index.mouse(reward_flags),iri,'.',...
            'markersize',5,...
            'color',clrs(ss,:));
        errorbar(sps(mm),...
            nanmean(data.reward.index.mouse(reward_flags)),...
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
    mouse_flags = data.mouse == mouse_ids{mm};
    
    % axes labels
    title(sps(mm),mouse_ids{mm},...
        'interpreter','none');
    xlabel(sps(mm),'Reward #');
    ylabel(sps(mm),'DA response');
    
    % iterate through sessions
    n_sessions = max(data.session(mouse_flags));
    clrs = cool(n_sessions);
    for ss = 1 : n_sessions
        session_flags = data.session == ss;
        reward_flags = ...
            mouse_flags & ...
            session_flags;
        if sum(reward_flags) == 0
            continue;
        end
        x = data.reward.index.mouse(reward_flags & valid_flags);
        X = [ones(size(x)),x];
        y = data.da.response(reward_flags & valid_flags);
        betas = robustfit(x,y);
        plot(sps(mm),...
            data.reward.index.mouse(reward_flags),...
            data.da.response(reward_flags),'.',...
            'markersize',10,...
            'color',[1,1,1]*.85);
        plot(sps(mm),...
            x,y,'.',...
            'markersize',15,...
            'color',clrs(ss,:));
        plot(sps(mm),...
            x,X*betas,'-w',...
            'linewidth',3);
        plot(sps(mm),...
            x,X*betas,'-',...
            'color',clrs(ss,:),...
            'linewidth',1.5);
    end
    reward_flags = ...
        mouse_flags;
    x = data.reward.index.mouse(reward_flags & valid_flags);
    X = [ones(size(x)),x];
    y = data.da.response(reward_flags & valid_flags);
    nan_flags = isnan(y);
    betas = robustfit(x,y);
    plot(sps(mm),...
        x,X*betas,'--k',...
        'linewidth',1);
end

%% replot fig3G (test 2)

% IRI type selection
iri_type = 'nominal';
% iri_type = 'actual';

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
    mouse_flags = data.mouse == mouse_ids{mm};
    
    % axes labels
    title(sps(mm),mouse_ids{mm},...
        'interpreter','none');
    xlabel(sps(mm),sprintf('Previous %s IRI (s)',iri_type));
    ylabel(sps(mm),'DA response');
    
    % iterate through sessions
    n_sessions = max(data.session(mouse_flags));
    clrs = cool(n_sessions);
    for ss = 1 : n_sessions
        session_flags = data.session == ss;
        reward_flags = ...
            mouse_flags & ...
            session_flags;
        if sum(reward_flags) == 0
            continue;
        end
        x = data.iri.(iri_type)(reward_flags & valid_flags);
        X = [ones(size(x)),x];
        y = data.da.response(reward_flags & valid_flags);
        betas = robustfit(x,y);
        scatter(sps(mm),...
            data.iri.(iri_type)(reward_flags),...
            data.da.response(reward_flags),15,...
            'markerfacecolor',[1,1,1]*.75,...
            'markeredgecolor','none',...
            'markerfacealpha',.25);
        scatter(sps(mm),...
            x,y,25,...
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
    reward_flags = ...
        mouse_flags;
    x = data.iri.(iri_type)(reward_flags & valid_flags);
    X = [ones(size(x)),x];
    y = data.da.response(reward_flags & valid_flags);
    nan_flags = isnan(y);
    betas = robustfit(x,y);
    [~,idcs] = sort(x);
    plot(sps(mm),...
        x(idcs),X(idcs,:)*betas,'--k',...
        'linewidth',1);
end

%% reward delivery-aligned average DA (split by session)

% figure initialization
figure(...
    'windowstyle','docked',...
    'numbertitle','off',...
    'name','da_delivery_session',...
    'color','w');

% axes initialization
sps = gobjects(n_mice,1);
for ii = 1 : n_mice
    sps(ii) = subplot(n_mice/4,n_mice/2,ii);
end
set(sps,...
    'xlim',[-1,1]*2.5,...
    'ylimspec','tight',...
    'xscale','linear',...
    'nextplot','add',...
    'linewidth',2,...
    'fontsize',12,...
    'tickdir','out');

% iterate through mice
for mm = 1 : n_mice
    mouse_flags = data.mouse == mouse_ids{mm};
    
    % axes labels
    title(sps(mm),mouse_ids{mm},...
        'interpreter','none');
    xlabel(sps(mm),'Time since reward delivery (s)');
    ylabel(sps(mm),'DA (\DeltaF/F)');
    
    % iterate through sessions
    n_sessions = max(data.session(mouse_flags));
    clrs = cool(n_sessions);
    for ss = 1 : n_sessions
        session_flags = data.session == ss;
        reward_flags = ...
            mouse_flags & ...
            session_flags & ...
            valid_flags;
        if sum(reward_flags) == 0
            continue;
        end
        da_mat = data.da.roi(reward_flags,:);
        da_mu = nanmean(da_mat,1);
        da_std = nanstd(da_mat,0,1);
        da_sem = da_std ./ sqrt(sum(reward_flags));
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

%% reward delivery-aligned average DA (split by training stage)

% figure initialization
figure(...
    'windowstyle','docked',...
    'numbertitle','off',...
    'name','da_delivery_stage',...
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
    
% quantile settings
n_quantiles = 3;
clrs = gray(n_quantiles+1);

% graphical object preallocation
p = gobjects(n_quantiles,1);

% iterate through mice
for mm = 1 : n_mice
    mouse_flags = data.mouse == mouse_ids{mm};
    
    % axes labels
    title(sps(mm),mouse_ids{mm},...
        'interpreter','none');
    xlabel(sps(mm),'Time since 1^{st} rewarding lick (s)');
    ylabel(sps(mm),'DA (\DeltaF/F)');
    
    % compute quantile boundaries
    n_trials = sum(mouse_flags);
    quantile_boundaries = floor(linspace(0,n_trials,n_quantiles+1));
    
    % iterate through quantiles
    for qq = 1 : n_quantiles
        quantile_flags = ...
            data.reward.index.mouse > quantile_boundaries(qq) & ...
            data.reward.index.mouse <= quantile_boundaries(qq+1);
        reward_flags = ...
            mouse_flags & ...
            quantile_flags & ...
            valid_flags;
        if sum(reward_flags) == 0
            continue;
        end
        da_mat = data.da.roi(reward_flags,:);
        da_mu = nanmean(da_mat,1);
        da_std = nanstd(da_mat,0,1);
        da_sem = da_std ./ sqrt(sum(reward_flags));
        nan_flags = isnan(da_mu) | isnan(isnan(da_sem)) | da_sem == 0;
        xpatch = [da_roi_time(~nan_flags),...
            fliplr(da_roi_time(~nan_flags))];
        ypatch = [da_mu(~nan_flags)-da_sem(~nan_flags),...
            fliplr(da_mu(~nan_flags)+da_sem(~nan_flags))];
        patch(sps(mm),...
            xpatch,ypatch,clrs(qq,:),...
            'edgecolor','none',...
            'facealpha',.25);
        p(qq) = plot(sps(mm),...
            da_roi_time(~nan_flags),da_mu(~nan_flags),'-',...
            'color',clrs(qq,:),...
            'linewidth',1);
    end
    
    % plot zero line
    plot(sps(mm),[0,0],ylim(sps(mm)),'--k');
    
    % legend
    legend(p,[{'early'},repmat({''},1,n_quantiles-2),{'late'}],...
        'box','off');
end

%% reward collection-aligned average DA (split by session)

% figure initialization
figure(...
    'windowstyle','docked',...
    'numbertitle','off',...
    'name','da_collection_session',...
    'color','w');

% axes initialization
sps = gobjects(n_mice,1);
for ii = 1 : n_mice
    sps(ii) = subplot(n_mice/4,n_mice/2,ii);
end
set(sps,...
    'xlim',[baseline_period(1),reward_period(2)],...
    'ylimspec','tight',...
    'xscale','linear',...
    'nextplot','add',...
    'linewidth',2,...
    'fontsize',12,...
    'tickdir','out');

% iterate through mice
for mm = 1 : n_mice
    mouse_flags = data.mouse == mouse_ids{mm};
    
    % axes labels
    title(sps(mm),mouse_ids{mm},...
        'interpreter','none');
    xlabel(sps(mm),'Time since 1^{st} rewarding lick (s)');
    ylabel(sps(mm),'DA (\DeltaF/F)');
    
    % iterate through sessions
    n_sessions = max(data.session(mouse_flags));
    clrs = cool(n_sessions);
    for ss = 1 : n_sessions
        session_flags = data.session == ss;
        reward_flags = ...
            mouse_flags & ...
            session_flags & ...
            valid_flags;
        if sum(reward_flags) == 0
            continue;
        end
        da_mat = [...
            data.da.baseline(reward_flags,1:end-1),...
            data.da.reward(reward_flags,:)];
        da_mu = nanmean(da_mat,1);
        da_std = nanstd(da_mat,0,1);
        da_sem = da_std ./ sqrt(sum(reward_flags));
        nan_flags = isnan(da_mu) | isnan(isnan(da_sem)) | da_sem == 0;
        da_time = unique([da_baseline_time,da_reward_time]);
        xpatch = [da_time(~nan_flags),...
            fliplr(da_time(~nan_flags))];
        ypatch = [da_mu(~nan_flags)-da_sem(~nan_flags),...
            fliplr(da_mu(~nan_flags)+da_sem(~nan_flags))];
        patch(sps(mm),...
            xpatch,ypatch,clrs(ss,:),...
            'edgecolor','none',...
            'facealpha',.25);
        plot(sps(mm),...
            da_time(~nan_flags),da_mu(~nan_flags),'-',...
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
        'linewidth',1.5);
    patch(sps(mm),...
        [reward_period,fliplr(reward_period)],...
        [-1,-1,1,1]*range(yylim)*.02+yymax,'k',...
        'edgecolor','k',...
        'facealpha',1,...
        'linewidth',1.5);
    
    % plot reference lines
    plot(sps(mm),[0,0],ylim(sps(mm)),'--k');
    plot(sps(mm),[1,1]*baseline_period(2),ylim(sps(mm)),'-k',...
        'linewidth',1);
end

%% reward collection-aligned average DA (split by training stage)

% figure initialization
figure(...
    'windowstyle','docked',...
    'numbertitle','off',...
    'name','da_collection_stage',...
    'color','w');

% axes initialization
sps = gobjects(n_mice,1);
for ii = 1 : n_mice
    sps(ii) = subplot(n_mice/4,n_mice/2,ii);
end
set(sps,...
    'xlim',[baseline_period(1),reward_period(2)],...
    'ylimspec','tight',...
    'xscale','linear',...
    'nextplot','add',...
    'linewidth',2,...
    'fontsize',12,...
    'tickdir','out');

% quantile settings
n_quantiles = 3;
clrs = gray(n_quantiles+1);

% graphical object preallocation
p = gobjects(n_quantiles,1);

% iterate through mice
for mm = 1 : n_mice
    mouse_flags = data.mouse == mouse_ids{mm};
    
    % axes labels
    title(sps(mm),mouse_ids{mm},...
        'interpreter','none');
    xlabel(sps(mm),'Time since 1^{st} rewarding lick (s)');
    ylabel(sps(mm),'DA (\DeltaF/F)');
    
    % compute quantile boundaries
    n_trials = sum(mouse_flags);
    quantile_boundaries = floor(linspace(0,n_trials,n_quantiles+1));
    
    % iterate through quantiles
    for qq = 1 : n_quantiles
        quantile_flags = ...
            data.reward.index.mouse > quantile_boundaries(qq) & ...
            data.reward.index.mouse <= quantile_boundaries(qq+1);
        reward_flags = ...
            mouse_flags & ...
            quantile_flags & ...
            valid_flags;
        if sum(reward_flags) == 0
            continue;
        end
        da_mat = [...
            data.da.baseline(reward_flags,1:end-1),...
            data.da.reward(reward_flags,:)];
        da_mu = nanmean(da_mat,1);
        da_std = nanstd(da_mat,0,1);
        da_sem = da_std ./ sqrt(sum(reward_flags));
        nan_flags = isnan(da_mu) | isnan(isnan(da_sem)) | da_sem == 0;
        da_time = unique([da_baseline_time,da_reward_time]);
        xpatch = [da_time(~nan_flags),...
            fliplr(da_time(~nan_flags))];
        ypatch = [da_mu(~nan_flags)-da_sem(~nan_flags),...
            fliplr(da_mu(~nan_flags)+da_sem(~nan_flags))];
        patch(sps(mm),...
            xpatch,ypatch,clrs(qq,:),...
            'edgecolor','none',...
            'facealpha',.25);
        p(qq) = plot(sps(mm),...
            da_time(~nan_flags),da_mu(~nan_flags),'-',...
            'color',clrs(qq,:),...
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
        'linewidth',1.5);
    patch(sps(mm),...
        [reward_period,fliplr(reward_period)],...
        [-1,-1,1,1]*range(yylim)*.02+yymax,'k',...
        'edgecolor','k',...
        'facealpha',1,...
        'linewidth',1.5);
    
    % plot reference lines
    plot(sps(mm),[0,0],ylim(sps(mm)),'--k');
    plot(sps(mm),[1,1]*baseline_period(2),ylim(sps(mm)),'-k',...
        'linewidth',1);
    
    % legend
    legend(p,[{'early'},repmat({''},1,n_quantiles-2),{'late'}],...
        'location','northwest',...
        'box','off');
end

%% reward delivery-aligned lick rate (split by session)

% figure initialization
figure(...
    'windowstyle','docked',...
    'numbertitle','off',...
    'name','licks_delivery_session',...
    'color','w');

% axes initialization
sps = gobjects(n_mice,1);
for ii = 1 : n_mice
    sps(ii) = subplot(n_mice/4,n_mice/2,ii);
end
set(sps,...
    'xlim',lick_period-lickrate_kernel.paddx,...
    'ylimspec','tight',...
    'xscale','linear',...
    'nextplot','add',...
    'linewidth',2,...
    'fontsize',12,...
    'tickdir','out');

% iterate through mice
for mm = 1 : n_mice
    mouse_flags = data.mouse == mouse_ids{mm};
    
    % axes labels
    title(sps(mm),mouse_ids{mm},...
        'interpreter','none');
    xlabel(sps(mm),'Time since reward delivery (s)');
    ylabel(sps(mm),'Lick rate (Hz)');
    
    % iterate through sessions
    n_sessions = max(data.session(mouse_flags));
    clrs = cool(n_sessions);
    for ss = 1 : n_sessions
        session_flags = data.session == ss;
        reward_flags = ...
            mouse_flags & ...
            session_flags & ...
            valid_flags;
        if sum(reward_flags) == 0
            continue;
        end
        
        % fetch relevant events & ensure no overlaps
        lick_counts = data.licks.delivery(reward_flags,:);
        nan_flags = isnan(lick_counts);
        lick_counts(nan_flags) = 0;
        lick_rates = conv2(1,lickrate_kernel.pdf,lick_counts,'same') / dt;
        lick_rates(nan_flags) = nan;
        lick_mu = nanmean(lick_rates,1);
        lick_std = nanstd(lick_rates,0,1);
        lick_sem = lick_std ./ sqrt(sum(~isnan(lick_rates)));
        nan_flags = isnan(lick_mu) | isnan(isnan(lick_sem)) | lick_sem == 0;
        xpatch = [lick_roi_time(~nan_flags),...
            fliplr(lick_roi_time(~nan_flags))];
        ypatch = [lick_mu(~nan_flags)-lick_sem(~nan_flags),...
            fliplr(lick_mu(~nan_flags)+lick_sem(~nan_flags))];
        patch(sps(mm),...
            xpatch,ypatch,clrs(ss,:),...
            'edgecolor','none',...
            'facealpha',.25);
        plot(sps(mm),...
            lick_roi_time(~nan_flags),lick_mu(~nan_flags),'-',...
            'color',clrs(ss,:),...
            'linewidth',1);
    end
    
    % plot zero line
    plot(sps(mm),[0,0],ylim(sps(mm)),'--k');
end

%% reward delivery-aligned lick rate (split by training stage)

% figure initialization
figure(...
    'windowstyle','docked',...
    'numbertitle','off',...
    'name','licks_delivery_stage',...
    'color','w');

% axes initialization
sps = gobjects(n_mice,1);
for ii = 1 : n_mice
    sps(ii) = subplot(n_mice/4,n_mice/2,ii);
end
set(sps,...
    'xlim',lick_period-lickrate_kernel.paddx,...
    'ylimspec','tight',...
    'xscale','linear',...
    'nextplot','add',...
    'linewidth',2,...
    'fontsize',12,...
    'tickdir','out');

% quantile settings
n_quantiles = 3;
clrs = gray(n_quantiles+1);

% graphical object preallocation
p = gobjects(n_quantiles,1);

% iterate through mice
for mm = 1 : n_mice
    mouse_flags = data.mouse == mouse_ids{mm};
    
    % axes labels
    title(sps(mm),mouse_ids{mm},...
        'interpreter','none');
    xlabel(sps(mm),'Time since 1^{st} rewarding lick (s)');
    ylabel(sps(mm),'Lick rate (Hz)');
    
    % compute quantile boundaries
    n_trials = sum(mouse_flags);
    quantile_boundaries = floor(linspace(0,n_trials,n_quantiles+1));
    
    % iterate through quantiles
    for qq = 1 : n_quantiles
        quantile_flags = ...
            data.reward.index.mouse > quantile_boundaries(qq) & ...
            data.reward.index.mouse <= quantile_boundaries(qq+1);
        reward_flags = ...
            mouse_flags & ...
            quantile_flags & ...
            valid_flags;
        if sum(reward_flags) == 0
            continue;
        end
        
        % fetch relevant events & ensure no overlaps
        lick_counts = data.licks.delivery(reward_flags,:);
        nan_flags = isnan(lick_counts);
        lick_counts(nan_flags) = 0;
        lick_rates = conv2(1,lickrate_kernel.pdf,lick_counts,'same') / dt;
        lick_rates(nan_flags) = nan;
        lick_mu = nanmean(lick_rates,1);
        lick_std = nanstd(lick_rates,0,1);
        lick_sem = lick_std ./ sqrt(sum(~isnan(lick_rates)));
        nan_flags = isnan(lick_mu) | isnan(isnan(lick_sem)) | lick_sem == 0;
        xpatch = [lick_roi_time(~nan_flags),...
            fliplr(lick_roi_time(~nan_flags))];
        ypatch = [lick_mu(~nan_flags)-lick_sem(~nan_flags),...
            fliplr(lick_mu(~nan_flags)+lick_sem(~nan_flags))];
        patch(sps(mm),...
            xpatch,ypatch,clrs(qq,:),...
            'edgecolor','none',...
            'facealpha',.25);
        p(qq) = plot(sps(mm),...
            lick_roi_time(~nan_flags),lick_mu(~nan_flags),'-',...
            'color',clrs(qq,:),...
            'linewidth',1);
    end
    
    % plot zero line
    plot(sps(mm),[0,0],ylim(sps(mm)),'--k');
    
    % legend
    legend(p,[{'early'},repmat({''},1,n_quantiles-2),{'late'}],...
        'box','off');
end

%% reward collection-aligned lick rate (split by session)

% figure initialization
figure(...
    'windowstyle','docked',...
    'numbertitle','off',...
    'name','licks_collection_session',...
    'color','w');

% axes initialization
sps = gobjects(n_mice,1);
for ii = 1 : n_mice
    sps(ii) = subplot(n_mice/4,n_mice/2,ii);
end
set(sps,...
    'xlim',lick_period-lickrate_kernel.paddx,...
    'ylimspec','tight',...
    'xscale','linear',...
    'nextplot','add',...
    'linewidth',2,...
    'fontsize',12,...
    'tickdir','out');

% iterate through mice
for mm = 1 : n_mice
    mouse_flags = data.mouse == mouse_ids{mm};
    
    % axes labels
    title(sps(mm),mouse_ids{mm},...
        'interpreter','none');
    xlabel(sps(mm),'Time since 1^{st} rewarding lick (s)');
    ylabel(sps(mm),'Lick rate (Hz)');
    
    % iterate through sessions
    n_sessions = max(data.session(mouse_flags));
    clrs = cool(n_sessions);
    for ss = 1 : n_sessions
        session_flags = data.session == ss;
        reward_flags = ...
            mouse_flags & ...
            session_flags & ...
            valid_flags;
        if sum(reward_flags) == 0
            continue;
        end
        
        % fetch relevant events & ensure no overlaps
        lick_counts = data.licks.collection(reward_flags,:);
        nan_flags = isnan(lick_counts);
        lick_counts(nan_flags) = 0;
        lick_rates = conv2(1,lickrate_kernel.pdf,lick_counts,'same') / dt;
        lick_rates(nan_flags) = nan;
        lick_mu = nanmean(lick_rates,1);
        lick_std = nanstd(lick_rates,0,1);
        lick_sem = lick_std ./ sqrt(sum(~isnan(lick_rates)));
        nan_flags = isnan(lick_mu) | isnan(isnan(lick_sem)) | lick_sem == 0;
        xpatch = [lick_roi_time(~nan_flags),...
            fliplr(lick_roi_time(~nan_flags))];
        ypatch = [lick_mu(~nan_flags)-lick_sem(~nan_flags),...
            fliplr(lick_mu(~nan_flags)+lick_sem(~nan_flags))];
        patch(sps(mm),...
            xpatch,ypatch,clrs(ss,:),...
            'edgecolor','none',...
            'facealpha',.25);
        plot(sps(mm),...
            lick_roi_time(~nan_flags),lick_mu(~nan_flags),'-',...
            'color',clrs(ss,:),...
            'linewidth',1);
    end
    
    % plot zero line
    plot(sps(mm),[0,0],ylim(sps(mm)),'--k');
end

%% reward collection-aligned lick rate (split by training stage)

% figure initialization
figure(...
    'windowstyle','docked',...
    'numbertitle','off',...
    'name','licks_collection_stage',...
    'color','w');

% axes initialization
sps = gobjects(n_mice,1);
for ii = 1 : n_mice
    sps(ii) = subplot(n_mice/4,n_mice/2,ii);
end
set(sps,...
    'xlim',lick_period-lickrate_kernel.paddx,...
    'ylimspec','tight',...
    'xscale','linear',...
    'nextplot','add',...
    'linewidth',2,...
    'fontsize',12,...
    'tickdir','out');

% quantile settings
n_quantiles = 3;
clrs = gray(n_quantiles+1);

% graphical object preallocation
p = gobjects(n_quantiles,1);

% iterate through mice
for mm = 1 : n_mice
    mouse_flags = data.mouse == mouse_ids{mm};
    
    % axes labels
    title(sps(mm),mouse_ids{mm},...
        'interpreter','none');
    xlabel(sps(mm),'Time since 1^{st} rewarding lick (s)');
    ylabel(sps(mm),'Lick rate (Hz)');
    
    % compute quantile boundaries
    n_trials = sum(mouse_flags);
    quantile_boundaries = floor(linspace(0,n_trials,n_quantiles+1));
    
    % iterate through quantiles
    for qq = 1 : n_quantiles
        quantile_flags = ...
            data.reward.index.mouse > quantile_boundaries(qq) & ...
            data.reward.index.mouse <= quantile_boundaries(qq+1);
        reward_flags = ...
            mouse_flags & ...
            quantile_flags & ...
            valid_flags;
        if sum(reward_flags) == 0
            continue;
        end
        
        % fetch relevant events & ensure no overlaps
        lick_counts = data.licks.collection(reward_flags,:);
        nan_flags = isnan(lick_counts);
        lick_counts(nan_flags) = 0;
        lick_rates = conv2(1,lickrate_kernel.pdf,lick_counts,'same') / dt;
        lick_rates(nan_flags) = nan;
        lick_mu = nanmean(lick_rates,1);
        lick_std = nanstd(lick_rates,0,1);
        lick_sem = lick_std ./ sqrt(sum(~isnan(lick_rates)));
        nan_flags = isnan(lick_mu) | isnan(isnan(lick_sem)) | lick_sem == 0;
        xpatch = [lick_roi_time(~nan_flags),...
            fliplr(lick_roi_time(~nan_flags))];
        ypatch = [lick_mu(~nan_flags)-lick_sem(~nan_flags),...
            fliplr(lick_mu(~nan_flags)+lick_sem(~nan_flags))];
        patch(sps(mm),...
            xpatch,ypatch,clrs(qq,:),...
            'edgecolor','none',...
            'facealpha',.25);
        p(qq) = plot(sps(mm),...
            lick_roi_time(~nan_flags),lick_mu(~nan_flags),'-',...
            'color',clrs(qq,:),...
            'linewidth',1);
    end
    
    % plot zero line
    plot(sps(mm),[0,0],ylim(sps(mm)),'--k');
    
    % legend
    legend(p,[{'early'},repmat({''},1,n_quantiles-2),{'late'}],...
        'box','off');
end