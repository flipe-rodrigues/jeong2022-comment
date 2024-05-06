%% preface
Jeong2022_dataPreface;

%% mouse settings
mouse_ids = mouse_ids(~ismember(mouse_ids,'HJ_FP_M8'));
n_mice = numel(mouse_ids);

%% experiment settings
experiment_id = 'poisson';
cs_dur = .25;
trace_dur = 3 - cs_dur;
us_delay = cs_dur + trace_dur;

%% session selection settings
session_start_idcs = struct(...
    'HJ_FP_F1',1,...
    'HJ_FP_F2',2,...
    'HJ_FP_M2',1,...3,...
    'HJ_FP_M3',1,...
    'HJ_FP_M4',1,...
    'HJ_FP_M6',1,...
    'HJ_FP_M7',1);...2);
session_stop_idcs = struct(...
    'HJ_FP_F1',inf,...4,...
    'HJ_FP_F2',inf,...5,...
    'HJ_FP_M2',inf,...4,...
    'HJ_FP_M3',inf,...2,...
    'HJ_FP_M4',inf,...3,...
    'HJ_FP_M6',inf,...3,...
    'HJ_FP_M7',inf);...4);


%% analysis parameters
trial_period = [0,max(us_delay)] + [-1,1] * 5;
baseline_period = [-.5,0];
roi_period = [0,.5];
stimulus_period = [-2,2];

%% selection criteria
iti_cutoff = -inf;
iei_cutoff = .5; % -inf;
nanify = false;

%% data parsing

% preallocation
cs_plus_labels = cell(n_mice,1);

% iterate through mice
for mm = 1 : n_mice
    progressreport(mm,n_mice,sprintf(...
        'parsing behavioral & photometry data (mouse %i/%i)',mm,n_mice));

    % parse mouse directory
    mouse_path = fullfile(mice_path,mouse_ids{mm},experiment_id);
    mouse_dir = dir(mouse_path);
    mouse_dir = mouse_dir(cellfun(@(x)~contains(x,'.'),{mouse_dir.name}));

    % initialize mouse counters
    mouse_session_idx = 1;
    mouse_trial_counter = 0;

    % parse session directory
    session_ids = {mouse_dir.name};

    % sort sessions chronologically
    days = cellfun(@(x) sscanf(x,'Day%i'),session_ids);
    [~,chrono_idcs] = sort(days);
    session_ids = session_ids(chrono_idcs);
    n_sessions = numel(session_ids);

    % iterate through sessions
    start_idx = session_start_idcs.(mouse_ids{mm});
    stop_idx = min(session_stop_idcs.(mouse_ids{mm}),n_sessions);
    for ss = start_idx : stop_idx
        session_path = fullfile(mouse_path,session_ids{ss});

        %% load behavioral data
        bhv_id = sprintf('%s_%s_eventlog.mat',...
            mouse_ids{mm},session_ids{ss});
        bhv_path = fullfile(session_path,bhv_id);
        load(bhv_path)

        %% parse events
        event_labels = categorical(...
            eventlog(:,1),[15,16,5,10,14,0],...
            {'CS1','CS2','lick','US','trial_end','session_end'});
        event_times = eventlog(:,2);
        nosolenoid_flags = eventlog(:,3);
        event_idcs = (1 : numel(event_labels))';
        start_idx = find(ismember(event_labels,{'CS1','CS2'}),1);
        end_idx = min(...
            find(event_labels == 'trial_end',1,'last') + 1,...
            find(event_labels == 'session_end'));
        if isempty(end_idx)
            end_idx = numel(event_labels);
        end
        session_dur = event_times(end_idx) - event_times(start_idx);

        %% event selection
        valid_flags = ...
            ~isundefined(event_labels) & ...
            ~nosolenoid_flags & ...
            event_idcs >= start_idx & ...
            event_idcs < end_idx;
        n_events = sum(valid_flags);
        event_idcs = (1 : n_events)';
        event_labels = removecats(event_labels(valid_flags),'end');
        event_times = event_times(valid_flags);

        %% parse US
        us_flags = event_labels == 'US';
        us_events = find(us_flags);
        us_times = event_times(us_flags);
        n_trials = sum(us_flags);
        trial_idcs = (1 : n_trials)';

        %% parse CS
        cs_flags = ismember(event_labels,{'CS1','CS2'});
        cs_events = find(cs_flags);
        cs_labels = event_labels(cs_flags);
        cs_times = event_times(cs_flags);
        cs_labels = cs_labels(trial_idcs);
        cs_times = cs_times(trial_idcs);

        %% parse CS+ and CS-
        if isempty(cs_plus_labels{mm})
            cs_plus_labels(mm) = ...
                cellstr(unique(cs_labels(~isnan(us_times))));
        end
        cs_signs = 2 * (cs_labels == cs_plus_labels{mm}) - 1;

        %% parse first licks after reward delivery
        lick_flags = event_labels == 'lick';

        % preallocation
        reward_times = nan(n_trials,1);

        % iterate through trials
        for ii = 1 : n_trials
            trial_idx = find(lick_flags & ...
                event_times >= us_times(ii),1,'first');
            if ~isempty(trial_idx)
                reward_times(ii) = event_times(trial_idx);
            end
        end

        %% compute inter-trial-intervals (ITI)
        iti = cs_times - [0;cs_times(1:end-1)+us_delay];

        %% compute inter-cue-intervals (ICI)
        ici = cs_times - [nan;cs_times(1:end-1)];

        %% compute intermediate CS-paired US intervals (CUI)
        cui = [us_times(2:end);inf]' - cs_times;
        cui(cui<0) = nan;
        cui = min(cui,[],2);

        %% compute inter-reward-intervals (ICI)
        iri = reward_times - [nan;reward_times(1:end-1)];

        %% compute inter-reward-intervals (IRI, nominal & actual)
        iri_nominal = nan(n_trials,1);
        iri_actual = nan(n_trials,1);
        iri_nominal(~isnan(us_times)) = ...
            diff([0;us_times((~isnan(us_times)))]);
        iri_actual(~isnan(reward_times)) = ...
            diff([0;reward_times((~isnan(reward_times)))]);

        %% parse reaction time
        reaction_times = reward_times - us_times;

        %% parse intermediate and previous "trials"
        intermediate_flags = ici < us_delay;
        trial_type = categorical(intermediate_flags,[0,1],...
            {'previous','intermediate'});

        %% load photometry data
        photometry_path = fullfile(session_path,'Photometry.mat');
        load(photometry_path);

        % renormalization
        if want2renormalize
            %                 f0 = abs(quantile(dff,.1));
            %                 dff = (dff - f0) ./ f0;
            dff = (dff - mean(dff)) ./ std(dff);
        end

        %% parse licks
        lick_times = event_times(lick_flags);
        lick_edges = event_times(1) : dt : event_times(end);
        lick_counts = histcounts(lick_times,lick_edges);

        % get lick-aligned snippets of lick counts
        [lick_cs_snippets,lick_cs_time] = signal2eventsnippets(...
            lick_edges(1:end-1),lick_counts,cs_times,...
            trial_period + lickrate_kernel.paddx,dt,nanify);
        [lick_reward_snippets,lick_reward_time] = signal2eventsnippets(...
            lick_edges(1:end-1),lick_counts,reward_times,...
            trial_period + lickrate_kernel.paddx,dt,nanify);

        %% compute inter-lick-intervals (ILI)
        ili_events = diff([nan;lick_times]);
        ili_idcs = sum(lick_times > cs_times',2);
        ili_trials = arrayfun(@(x)ili_events(ili_idcs == x),trial_idcs,...
            'uniformoutput',false);

        %% parse photometry data

        % correct for nonstationary sampling frequency
        time = T(1) : dt : T(end);
        da = interp1(T,dff,time);

        % get event-aligned snippets of DA
        [da_baseline_snippets,~] = signal2eventsnippets(...
            time,da,cs_times,baseline_period,dt,nanify);
        [da_cs_roi_snippets,~] = signal2eventsnippets(...
            time,da,cs_times,roi_period,dt,nanify);
        [da_us_roi_snippets,~] = signal2eventsnippets(...
            time,da,us_times,roi_period,dt,nanify);
        [da_reward_roi_snippets,~] = signal2eventsnippets(...
            time,da,reward_times,roi_period,dt,nanify);
        [da_cs_snippets,da_cs_time] = signal2eventsnippets(...
            time,da,cs_times,trial_period,dt,nanify);
        [da_reward_snippets,da_reward_time] = signal2eventsnippets(...
            time,da,reward_times,trial_period,dt,nanify);

        % preallocation
        da_cs_response = nan(n_trials,1);
        da_reward_response = nan(n_trials,1);

        % iterate through trials
        for ii = 1 : n_trials

            % compute 'DA response' metric
            da_cs_response(ii) = ...
                sum(da_cs_roi_snippets(ii,:) * dt) / range(roi_period) - ...
                sum(da_baseline_snippets(ii,:) * dt) / range(baseline_period);
            da_reward_response(ii) = ...
                sum(da_reward_roi_snippets(ii,:) * dt) / range(roi_period) - ...
                sum(da_baseline_snippets(ii,:) * dt) / range(baseline_period);
        end

        %% organize session data into tables

        % construct trial table
        index_table = table(...
            trial_idcs + mouse_trial_counter,...
            trial_idcs,...
            'variablenames',{...
            'mouse',...
            'session',...
            });

        % construct time table
        time_table = table(...
            cs_times,...
            cs_times+cs_dur,...
            us_times,...
            reward_times,...
            'variablenames',{...
            'cs_onset',...
            'cs_offset',...
            'us',...
            'reward',...
            });

        % construct CS table
        cs_table = table(...
            cs_labels,...
            cs_signs,...
            repmat(cs_dur,n_trials,1),...
            'variablenames',{...
            'label',...
            'sign',...
            'dur',...
            });

        % construct trial table
        trial_table = table(...
            index_table,...
            time_table,...
            cs_table,...
            trial_type,...
            'variablenames',{...
            'index',...
            'time',...
            'cs',...
            'type',...
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
            lick_cs_snippets,...
            lick_reward_snippets,...
            'variablenames',{...
            'cs',...
            'reward'});

        % construct DA table
        da_table = table(...
            da_cs_snippets,...
            da_reward_snippets,...
            da_cs_response,...
            da_reward_response,...
            'variablenames',{...
            'cs',...
            'reward',...
            'cs_response',...
            'reward_response'});

        % concatenate into a session table
        session_data = table(...
            categorical(cellstr(repmat(mouse_ids{mm},n_trials,1)),mouse_ids),...
            repmat(mouse_session_idx,n_trials,1),...
            trial_table,...
            iti,...
            ici,...
            cui,...
            iri,...
            reaction_times,...
            lick_table,...
            ili_trials,...
            da_table,...
            'variablenames',{...
            'mouse',...
            'session',...
            'trial'...
            'iti',...
            'ici',...
            'cui',...
            'iri',...
            'rt',...
            'lick',...
            'ili',...
            'da',...
            });

        % append to the current mouse's table
        if mouse_session_idx == 1
            mouse_data = session_data;
        else
            mouse_data = [mouse_data; session_data];
        end

        % increment mouse counters
        mouse_session_idx = mouse_session_idx + 1;
        mouse_trial_counter = mouse_trial_counter + n_trials;
    end

    % append to the final data table
    if mm == 1
        data = mouse_data;
    else
        data = [data; mouse_data];
    end
end

%% selection criteria
iti_flags = ...
    data.iti >= iti_cutoff & ...
    [data.iti(2:end); nan] >= iti_cutoff;
iei_flags = ...
    data.ici >= iei_cutoff & ...
    data.cui >= iei_cutoff;
rwd_flags = ...
    data.trial.time.reward ~= [data.trial.time.reward(2:end); nan] & ...
    data.trial.time.reward ~= [nan; data.trial.time.reward(1:end-1)];
nan_flags = all(isnan(data.da.cs),2);
valid_flags = ...
    iti_flags & ...
    iei_flags & ...
    rwd_flags & ...
    ~nan_flags;

%% trial type settings
trial_type_labels = categories(data.trial.type);
n_types = numel(trial_type_labels);
type_clrs = colorlerp([[0.2,0.3,0.3];[1,.65,0]],n_types);

%% reaction time bin settings
rt_binwidth = 1 / 15;
rt_roi = [trial_period(1),trial_period(2)];
rt_edges = rt_roi(1) : rt_binwidth : rt_roi(2);

%% flag rewarded trials
reward_flags = ~isnan(data.trial.time.reward);

%% CS onset-aligned DA & lick rasters (sorted chronologically)

% iterate through mice
for mm = 1 : n_mice

    % figure initialization
    figure(...
        'windowstyle','docked',...
        'numbertitle','off',...
        'name',sprintf('%s_%s_cs_chronological',...
        strrep(mouse_ids{mm},'_',''),experiment_id),...
        'color','w');

    % axes initialization
    n_rows = 1;
    n_cols = 2;
    n_sps = n_rows * n_cols;
    sps = gobjects(n_sps,1);
    for ii = 1 : n_sps
        sps(ii) = subplot(n_rows,n_cols,ii);
        xlabel(sps(ii),'Time since CS onset (s)');
        ylabel(sps(ii),'Trial # (sorted chronologically)');
    end
    set(sps,...
        'xlim',trial_period,...
        'ylimspec','tight',...
        'xscale','linear',...
        'nextplot','add',...
        'colormap',bone(2^8-1),...
        'linewidth',2,...
        'fontsize',12,...
        'layer','top',...
        'tickdir','out');

    % figure pseudo title
    annotation(...
        'textbox',[0,.95,1,.05],...
        'string',sprintf('%s',mouse_ids{mm}),...
        'fontsize',14,...
        'fontweight','bold',...
        'horizontalalignment','center',...
        'verticalalignment','bottom',...
        'linestyle','none',...
        'interpreter','none');

    % axes titles
    title(sps(1),'DA (\DeltaF/F)');
    title(sps(2),'Lick rate');

    % trial selection
    mouse_flags = data.mouse == mouse_ids{mm};
    trial_flags = ...
        valid_flags & ...
        mouse_flags;
    n_trials = sum(trial_flags);
    n_sessions = max(data.session(mouse_flags));
    session_clrs = cool(n_sessions);

    % parse DA data
    da_mat = data.da.cs(trial_flags,:);

    % parse lick data
    lick_counts = data.lick.cs(trial_flags,:);
    nan_flags = isnan(lick_counts);
    lick_counts(nan_flags) = 0;
    lick_mat = conv2(1,lickrate_kernel.pdf,lick_counts,'same') / dt;
    lick_mat(nan_flags) = nan;

    % parse behavioral data
    ici = data.ici(trial_flags);
    cui = data.cui(trial_flags);
    reaction_times = data.rt(trial_flags);
    us_delays = data.trial.cs.dur(trial_flags) + trace_dur;
    session_idcs = data.session(trial_flags);

    % trial sorting
    sorting_mat = [...
        double(data.trial.cs.label(trial_flags)),...
        data.session(trial_flags),...
        data.rt(trial_flags),...
        double(data.trial.type(trial_flags)),...
        data.ici(trial_flags),...
        data.cui(trial_flags)];
    [~,sorted_idcs] = sortrows(sorting_mat,[1,2,4]);

    % plot DA raster
    imagesc(sps(1),da_cs_time,[],...
        da_mat(sorted_idcs,:),quantile(da_mat,[.001,.999],'all')');
    imagesc(sps(2),lick_cs_time,[],...
        lick_mat(sorted_idcs,:),[0,8.5]);

    % iterate through rasters
    for ii = 1 : n_sps

        % plot intermediate "trials"
        scatter(sps(ii),...
            -ici(sorted_idcs),1:n_trials,30,...
            type_clrs(2,:),...
            'marker','.');

        % plot reaction times
        scatter(sps(ii),...
            us_delays(sorted_idcs)+reaction_times(sorted_idcs),1:n_trials,5,...
            session_clrs(session_idcs(sorted_idcs),:),...
            'marker','.');

        % iterate through sessions
        counter = 0;
        for ss = 1 : n_sessions
            session_flags = data.session == ss;
            trial_flags = ...
                valid_flags & ...
                mouse_flags & ...
                session_flags;
            prev_counter = counter;
            counter = counter + sum(trial_flags);

            % plot session delimeters
            plot(sps(ii),xlim(sps(ii)),...
                [1,1]*(counter+.5),...
                'color',[1,1,1],...
                'linestyle',':');
            plot(sps(ii),[1,1]*min(xlim(sps(ii)))+.01*range(xlim(sps(ii))),...
                [prev_counter,counter]+.5,...
                'color',session_clrs(ss,:),...
                'linewidth',5);
        end

        % plot reference lines
        plot(sps(ii),xlim(sps(ii)),...
            [1,1]*(sum(data.trial.cs.label(mouse_flags & valid_flags)=='CS1')+.5),...
            'color',[1,1,1],...
            'linewidth',1.5);
        plot(sps(ii),[0,0],ylim(sps(ii)),'--w');
        plot(sps(ii),[0,0]+cs_dur,ylim(sps(ii)),'--w');
        plot(sps(ii),[0,0]+cs_dur+trace_dur,ylim(sps(ii)),'--w');
    end

    % save figure
    if want2save
        png_file = fullfile(panel_path,[get(gcf,'name'),'.png']);
        print(gcf,png_file,'-dpng','-r300','-painters');
    end
end

%% reward-aligned DA & lick rasters (sorted by reaction time)

% iterate through mice
for mm = 1 : n_mice

    % figure initialization
    figure(...
        'windowstyle','docked',...
        'numbertitle','off',...
        'name',sprintf('%s_%s_reward_reaction',...
        strrep(mouse_ids{mm},'_',''),experiment_id),...
        'color','w');

    % axes initialization
    n_rows = 1;
    n_cols = 2;
    n_sps = n_rows * n_cols;
    sps = gobjects(n_sps,1);
    for ii = 1 : n_sps
        sps(ii) = subplot(n_rows,n_cols,ii);
        xlabel(sps(ii),'Time since reward collection (s)');
        ylabel(sps(ii),'Trial # (sorted by reaction time)');
    end
    set(sps,...
        'xlim',trial_period,...
        'ylimspec','tight',...
        'xscale','linear',...
        'nextplot','add',...
        'colormap',bone(2^8-1),...
        'linewidth',2,...
        'fontsize',12,...
        'layer','top',...
        'tickdir','out');

    % figure pseudo title
    annotation(...
        'textbox',[0,.95,1,.05],...
        'string',sprintf('%s',mouse_ids{mm}),...
        'fontsize',14,...
        'fontweight','bold',...
        'horizontalalignment','center',...
        'verticalalignment','bottom',...
        'linestyle','none',...
        'interpreter','none');

    % axes titles
    title(sps(1),'DA (\DeltaF/F)');
    title(sps(2),'Lick rate');

    % trial selection
    mouse_flags = data.mouse == mouse_ids{mm};
    trial_flags = ...
        valid_flags & ...
        mouse_flags & ...
        reward_flags;
    n_trials = sum(trial_flags);
    n_sessions = max(data.session(mouse_flags));
    session_clrs = cool(n_sessions);

    % parse DA data
    da_mat = data.da.reward(trial_flags,:);

    % parse lick data
    lick_counts = data.lick.reward(trial_flags,:);
    nan_flags = isnan(lick_counts);
    lick_counts(nan_flags) = 0;
    lick_mat = conv2(1,lickrate_kernel.pdf,lick_counts,'same') / dt;
    lick_mat(nan_flags) = nan;

    % parse behavioral data
    ici = data.ici(trial_flags);
    cui = data.cui(trial_flags);
    iri = data.iri(trial_flags);
    reaction_times = data.rt(trial_flags);
    us_delays = data.trial.cs.dur(trial_flags) + trace_dur;
    session_idcs = data.session(trial_flags);

    % trial sorting
    sorting_mat = [...
        double(data.trial.cs.label(trial_flags)),...
        data.session(trial_flags),...
        data.rt(trial_flags),...
        double(data.trial.type(trial_flags)),...
        data.ici(trial_flags),...
        data.iri(trial_flags)];
    [~,sorted_idcs] = sortrows(sorting_mat,[1,2,4,3]);

    % plot DA raster
    imagesc(sps(1),da_reward_time,[],...
        da_mat(sorted_idcs,:),quantile(da_mat,[.001,.999],'all')');
    imagesc(sps(2),lick_reward_time,[],...
        lick_mat(sorted_idcs,:),[0,8.5]);

    % iterate through rasters
    for ii = 1 : n_sps

        % plot intermediate "trials"
        scatter(sps(ii),...
            -iri(sorted_idcs)-reaction_times(sorted_idcs),1:n_trials,30,...
            type_clrs(2,:),...
            'marker','.');

        % plot reaction times
        scatter(sps(ii),...
            -reaction_times(sorted_idcs),1:n_trials,5,...
            session_clrs(session_idcs(sorted_idcs),:),...
            'marker','.');

        % iterate through sessions
        counter = 0;
        for ss = 1 : n_sessions
            session_flags = data.session == ss;
            trial_flags = ...
                valid_flags & ...
                mouse_flags & ...
                session_flags & ...
                reward_flags;
            prev_counter = counter;
            counter = counter + sum(trial_flags);

            % plot session delimeters
            plot(sps(ii),xlim(sps(ii)),...
                [1,1]*(counter+.5),...
                'color',[1,1,1],...
                'linestyle',':');
            plot(sps(ii),[1,1]*min(xlim(sps(ii)))+.01*range(xlim(sps(ii))),...
                [prev_counter,counter]+.5,...
                'color',session_clrs(ss,:),...
                'linewidth',5);
        end

        % plot reference lines
        plot(sps(ii),[0,0],ylim(sps(ii)),'--w');
        plot(sps(ii),[0,0]+cs_dur,ylim(sps(ii)),'--w');
        plot(sps(ii),[0,0]+cs_dur+trace_dur,ylim(sps(ii)),'--w');
    end

    % save figure
    if want2save
        png_file = fullfile(panel_path,[get(gcf,'name'),'.png']);
        print(gcf,png_file,'-dpng','-r300','-painters');
    end
end

%% CS+ onset-aligned average DA (split by session)

% figure initialization
figure(...
    'windowstyle','docked',...
    'numbertitle','off',...
    'name','poisson_da_cs+_session',...
    'color','w');

% axes initialization
sps = gobjects(n_mice,1);
for ii = 1 : n_mice
    sps(ii) = subplot(ceil(n_mice/4),ceil(n_mice/2),ii);
end
set(sps,...
    'xlim',stimulus_period,...
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
    title(sps(mm),sprintf('%s',mouse_ids{mm}),...
        'interpreter','none');
    xlabel(sps(mm),'Time since CS+ onset (s)');
    ylabel(sps(mm),'DA (\DeltaF/F)');

    % iterate through sessions
    n_sessions = max(data.session(mouse_flags));
    session_clrs = cool(n_sessions);
    for ss = 1 : n_sessions
        session_flags = data.session == ss;
        trial_flags = ...
            valid_flags & ...
            mouse_flags & ...
            session_flags;
        if sum(trial_flags) == 0
            continue;
        end
        da_mat = data.da.cs(trial_flags,:);
        da_mu = nanmean(da_mat,1);
        da_std = nanstd(da_mat,0,1);
        da_sem = da_std ./ sqrt(sum(trial_flags));
        nan_flags = isnan(da_mu) | isnan(isnan(da_sem)) | da_sem == 0;
        xpatch = [da_cs_time(~nan_flags),...
            fliplr(da_cs_time(~nan_flags))];
        ypatch = [da_mu(~nan_flags)-da_sem(~nan_flags),...
            fliplr(da_mu(~nan_flags)+da_sem(~nan_flags))];
        patch(sps(mm),...
            xpatch,ypatch,session_clrs(ss,:),...
            'edgecolor','none',...
            'facealpha',.25);
        plot(sps(mm),...
            da_cs_time(~nan_flags),da_mu(~nan_flags),'-',...
            'color',session_clrs(ss,:),...
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
        [roi_period,fliplr(roi_period)],...
        [-1,-1,1,1]*range(yylim)*.02+yymax,'k',...
        'edgecolor','k',...
        'facealpha',1,...
        'linewidth',1.5);

    % plot reference lines
    plot(sps(mm),[0,0],ylim(sps(mm)),'--k');
    plot(sps(mm),[1,1]*baseline_period(2),ylim(sps(mm)),'-k',...
        'linewidth',1);
end

% save figure
if want2save
    png_file = fullfile(panel_path,[get(gcf,'name'),'.png']);
    print(gcf,png_file,'-dpng','-r300','-painters');
end

%% CS+ onset-aligned average DA (split by trial type)

% figure initialization
figure(...
    'windowstyle','docked',...
    'numbertitle','off',...
    'name','poisson_da_cs+_type',...
    'color','w');

% axes initialization
sps = gobjects(n_mice,1);
for ii = 1 : n_mice
    sps(ii) = subplot(ceil(n_mice/4),ceil(n_mice/2),ii);
end
set(sps,...
    'xlim',stimulus_period,...
    'ylimspec','tight',...
    'xscale','linear',...
    'nextplot','add',...
    'linewidth',2,...
    'fontsize',12,...
    'tickdir','out');

% graphical object preallocation
p = gobjects(n_types,1);

% iterate through mice
for mm = 1 : n_mice
    mouse_flags = data.mouse == mouse_ids{mm};

    % axes labels
    title(sps(mm),sprintf('%s',mouse_ids{mm}),...
        'interpreter','none');
    xlabel(sps(mm),'Time since CS+ onset (s)');
    ylabel(sps(mm),'DA (\DeltaF/F)');

    % iterate through trial types
    for tt = 1 : n_types
        type_flags = data.trial.type == trial_type_labels{tt};
        trial_flags = ...
            valid_flags & ...
            mouse_flags & ...
            type_flags;
        if sum(trial_flags) == 0
            continue;
        end
        da_mat = data.da.cs(trial_flags,:);
        da_mu = nanmean(da_mat,1);
        da_std = nanstd(da_mat,0,1);
        da_sem = da_std ./ sqrt(sum(trial_flags));
        nan_flags = isnan(da_mu) | isnan(isnan(da_sem)) | da_sem == 0;
        xpatch = [da_cs_time(~nan_flags),...
            fliplr(da_cs_time(~nan_flags))];
        ypatch = [da_mu(~nan_flags)-da_sem(~nan_flags),...
            fliplr(da_mu(~nan_flags)+da_sem(~nan_flags))];
        patch(sps(mm),...
            xpatch,ypatch,type_clrs(tt,:),...
            'edgecolor','none',...
            'facealpha',.25);
        p(tt) = plot(sps(mm),...
            da_cs_time(~nan_flags),da_mu(~nan_flags),'-',...
            'color',type_clrs(tt,:),...
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
        [roi_period,fliplr(roi_period)],...
        [-1,-1,1,1]*range(yylim)*.02+yymax,'k',...
        'edgecolor','k',...
        'facealpha',1,...
        'linewidth',1.5);

    % plot reference lines
    plot(sps(mm),[0,0],ylim(sps(mm)),'--k');
    plot(sps(mm),[1,1]*baseline_period(2),ylim(sps(mm)),'-k',...
        'linewidth',1);

    % legend
    legend(p,trial_type_labels,...
        'location','northwest',...
        'box','off');
end

% save figure
if want2save
    png_file = fullfile(panel_path,[get(gcf,'name'),'.png']);
    print(gcf,png_file,'-dpng','-r300','-painters');
end

%% reward-aligned average DA (split by session)

% figure initialization
figure(...
    'windowstyle','docked',...
    'numbertitle','off',...
    'name','poisson_da_reward_session',...
    'color','w');

% axes initialization
sps = gobjects(n_mice,1);
for ii = 1 : n_mice
    sps(ii) = subplot(ceil(n_mice/4),ceil(n_mice/2),ii);
end
set(sps,...
    'xlim',stimulus_period,...
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
    title(sps(mm),sprintf('%s',mouse_ids{mm}),...
        'interpreter','none');
    xlabel(sps(mm),'Time since reward collection (s)');
    ylabel(sps(mm),'DA (\DeltaF/F)');

    % iterate through sessions
    n_sessions = max(data.session(mouse_flags));
    session_clrs = cool(n_sessions);
    for ss = 1 : n_sessions
        session_flags = data.session == ss;
        trial_flags = ...
            valid_flags & ...
            mouse_flags & ...
            session_flags;
        if sum(trial_flags) == 0
            continue;
        end
        da_mat = data.da.reward(trial_flags,:);
        da_mu = nanmean(da_mat,1);
        da_std = nanstd(da_mat,0,1);
        da_sem = da_std ./ sqrt(sum(trial_flags));
        nan_flags = isnan(da_mu) | isnan(isnan(da_sem)) | da_sem == 0;
        xpatch = [da_reward_time(~nan_flags),...
            fliplr(da_reward_time(~nan_flags))];
        ypatch = [da_mu(~nan_flags)-da_sem(~nan_flags),...
            fliplr(da_mu(~nan_flags)+da_sem(~nan_flags))];
        patch(sps(mm),...
            xpatch,ypatch,session_clrs(ss,:),...
            'edgecolor','none',...
            'facealpha',.25);
        plot(sps(mm),...
            da_reward_time(~nan_flags),da_mu(~nan_flags),'-',...
            'color',session_clrs(ss,:),...
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
        [roi_period,fliplr(roi_period)],...
        [-1,-1,1,1]*range(yylim)*.02+yymax,'k',...
        'edgecolor','k',...
        'facealpha',1,...
        'linewidth',1.5);

    % plot reference lines
    plot(sps(mm),[0,0],ylim(sps(mm)),'--k');
    plot(sps(mm),[1,1]*baseline_period(2),ylim(sps(mm)),'-k',...
        'linewidth',1);
end

% save figure
if want2save
    png_file = fullfile(panel_path,[get(gcf,'name'),'.png']);
    print(gcf,png_file,'-dpng','-r300','-painters');
end

%% reward-aligned average DA (split by trial type)

% figure initialization
figure(...
    'windowstyle','docked',...
    'numbertitle','off',...
    'name','poisson_da_reward_type',...
    'color','w');

% axes initialization
sps = gobjects(n_mice,1);
for ii = 1 : n_mice
    sps(ii) = subplot(ceil(n_mice/4),ceil(n_mice/2),ii);
end
set(sps,...
    'xlim',stimulus_period,...
    'ylimspec','tight',...
    'xscale','linear',...
    'nextplot','add',...
    'linewidth',2,...
    'fontsize',12,...
    'tickdir','out');

% graphical object preallocation
p = gobjects(n_types,1);

% iterate through mice
for mm = 1 : n_mice
    mouse_flags = data.mouse == mouse_ids{mm};

    % axes labels
    title(sps(mm),sprintf('%s',mouse_ids{mm}),...
        'interpreter','none');
    xlabel(sps(mm),'Time since reward collection (s)');
    ylabel(sps(mm),'DA (\DeltaF/F)');

    % iterate through trial types
    for tt = 1 : n_types
        type_flags = data.trial.type == trial_type_labels{tt};
        trial_flags = ...
            valid_flags & ...
            mouse_flags & ...
            type_flags;
        if sum(trial_flags) == 0
            continue;
        end
        da_mat = data.da.reward(trial_flags,:);
        da_mu = nanmean(da_mat,1);
        da_std = nanstd(da_mat,0,1);
        da_sem = da_std ./ sqrt(sum(trial_flags));
        nan_flags = isnan(da_mu) | isnan(isnan(da_sem)) | da_sem == 0;
        xpatch = [da_reward_time(~nan_flags),...
            fliplr(da_reward_time(~nan_flags))];
        ypatch = [da_mu(~nan_flags)-da_sem(~nan_flags),...
            fliplr(da_mu(~nan_flags)+da_sem(~nan_flags))];
        patch(sps(mm),...
            xpatch,ypatch,type_clrs(tt,:),...
            'edgecolor','none',...
            'facealpha',.25);
        p(tt) = plot(sps(mm),...
            da_reward_time(~nan_flags),da_mu(~nan_flags),'-',...
            'color',type_clrs(tt,:),...
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
        [roi_period,fliplr(roi_period)],...
        [-1,-1,1,1]*range(yylim)*.02+yymax,'k',...
        'edgecolor','k',...
        'facealpha',1,...
        'linewidth',1.5);

    % plot reference lines
    plot(sps(mm),[0,0],ylim(sps(mm)),'--k');
    plot(sps(mm),[1,1]*baseline_period(2),ylim(sps(mm)),'-k',...
        'linewidth',1);

    % legend
    legend(p,trial_type_labels,...
        'location','northwest',...
        'box','off');
end

%% plot CS+ response dynamics

% figure initialization
figure(...
    'windowstyle','docked',...
    'numbertitle','off',...
    'name','cs+_response',...
    'color','w');

% axes initialization
sps = gobjects(n_mice,1);
for ii = 1 : n_mice
    sps(ii) = subplot(ceil(n_mice/4),ceil(n_mice/2),ii);
end
set(sps,...
    'xlimspec','tight',...
    'xtick',0:100:max(data.trial.index.mouse),...
    'ylimspec','tight',...
    'nextplot','add',...
    'linewidth',2,...
    'fontsize',12,...
    'tickdir','out');

% iterate through mice
for mm = 1 : n_mice
    mouse_flags = data.mouse == mouse_ids{mm};

    % axes labels
    title(sps(mm),sprintf('%s',mouse_ids{mm}),...
        'interpreter','none');
    xlabel(sps(mm),'Trial #');
    ylabel(sps(mm),'DA CS+ response');

    % iterate through sessions
    n_sessions = max(data.session(mouse_flags));
    session_clrs = cool(n_sessions);
    for ss = 1 : n_sessions
        session_flags = data.session == ss;
        trial_flags = ...
            valid_flags & ...
            mouse_flags & ...
            session_flags & ...
            reward_flags;
        if sum(trial_flags) == 0
            continue;
        end
        x = data.trial.index.mouse(trial_flags);
        X = [ones(size(x)),x];
        y = data.da.cs_response(trial_flags);
        betas = robustfit(x,y);
        plot(sps(mm),...
            x,y,'.',...
            'markersize',15,...
            'color',session_clrs(ss,:));
        plot(sps(mm),...
            x,X*betas,'-w',...
            'linewidth',3);
        plot(sps(mm),...
            x,X*betas,'-',...
            'color',session_clrs(ss,:),...
            'linewidth',1.5);
    end
    trial_flags = ...
        valid_flags & ...
        mouse_flags & ...
        reward_flags;
    x = data.trial.index.mouse(trial_flags);
    X = [ones(size(x)),x];
    y = data.da.cs_response(trial_flags);
    nan_flags = isnan(y);
    betas = robustfit(x,y);
    plot(sps(mm),...
        x,X*betas,'--k',...
        'linewidth',1);
end

%% plot US response dynamics

% figure initialization
figure(...
    'windowstyle','docked',...
    'numbertitle','off',...
    'name','us_response',...
    'color','w');

% axes initialization
sps = gobjects(n_mice,1);
for ii = 1 : n_mice
    sps(ii) = subplot(ceil(n_mice/4),ceil(n_mice/2),ii);
end
set(sps,...
    'xlimspec','tight',...
    'xtick',0:100:max(data.trial.index.mouse),...
    'ylimspec','tight',...
    'nextplot','add',...
    'linewidth',2,...
    'fontsize',12,...
    'tickdir','out');

% iterate through mice
for mm = 1 : n_mice
    mouse_flags = data.mouse == mouse_ids{mm};

    % axes labels
    title(sps(mm),sprintf('%s',mouse_ids{mm}),...
        'interpreter','none');
    xlabel(sps(mm),'Trial #');
    ylabel(sps(mm),'DA initial US response');

    % iterate through sessions
    n_sessions = max(data.session(mouse_flags));
    session_clrs = cool(n_sessions);
    for ss = 1 : n_sessions
        session_flags = data.session == ss;
        trial_flags = ...
            valid_flags & ...
            mouse_flags & ...
            session_flags & ...
            reward_flags;
        if sum(trial_flags) == 0
            continue;
        end
        x = data.trial.index.mouse(trial_flags);
        X = [ones(size(x)),x];
        y = data.da.reward_response(trial_flags);
        betas = robustfit(x,y);
        plot(sps(mm),...
            x,y,'.',...
            'markersize',15,...
            'color',session_clrs(ss,:));
        plot(sps(mm),...
            x,X*betas,'-w',...
            'linewidth',3);
        plot(sps(mm),...
            x,X*betas,'-',...
            'color',session_clrs(ss,:),...
            'linewidth',1.5);
    end
    trial_flags = ...
        valid_flags & ...
        mouse_flags & ...
        reward_flags;
    x = data.trial.index.mouse(trial_flags);
    X = [ones(size(x)),x];
    y = data.da.reward_response(trial_flags);
    nan_flags = isnan(y);
    betas = robustfit(x,y);
    plot(sps(mm),...
        x,X*betas,'--k',...
        'linewidth',1);
end