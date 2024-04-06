%% preface
Jeong2022_dataPreface;

%% meta data
meta = struct();
meta.experiment = 'randomrewards';
meta.epochs.delivery = [-1,1] * 10;
meta.epochs.collection = [-1,1] * 10;
meta.epochs.baseline = [-2,-.5];
meta.epochs.reward = [-.5,1];
meta.mice.n = n_mice;
meta.mice.ids = cellfun(@(x)x(end-1:end),mouse_ids,...
    'uniformoutput',false);

%% data parsing

% preallocation
reaction_times_cell = cell(n_mice,1);
lick_times_cell = cell(n_mice,1);

% iterate through mice
for mm = 1 : n_mice
    
    % parse mouse directory
    mouse_path = fullfile(mice_path,mouse_ids{mm},meta.experiment);
    mouse_dir = dir(mouse_path);
    mouse_dir = mouse_dir(cellfun(@(x)~contains(x,'.'),{mouse_dir.name}));
    
    % parse session directory
    session_ids = {mouse_dir.name};
    session_days = cellfun(@(x)str2double(strrep(x,'Day','')),session_ids);
    n_sessions = numel(session_ids);
    
    % sort sessions chronologically
    days = cellfun(@(x) sscanf(x,'Day%i'),session_ids);
    [~,chrono_idcs] = sort(days);
    session_ids = session_ids(chrono_idcs);
    
    % initialize mouse counters
    mouse_reward_counter = 0;
    
    % animal-specific session selection
    if contains(mouse_ids{mm},'M2')
        n_sessions = 7;
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
        start_idx = find(event_labels == 'lick',1);
        end_idx = find(event_labels == 'end');
        session_dur = event_times(end_idx) - event_times(start_idx);
        
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
        
        %% parse second licks after reward delivery
        % _________________________________________
        
        %% compute inter-reward-intervals (IRI, nominal & actual)
        iri_nominal = diff([0;reward_times]);
        iri_actual = diff([0;firstlick_times]);
        
        %% parse reaction time
        reaction_times = firstlick_times - reward_times;
        
        %% load photometry data
        photometry_path = fullfile(session_path,'Photometry.mat');
        load(photometry_path);
        
        % renormalization
        if want2renormalize
%             f0 = abs(quantile(dff,.1));
%             dff = (dff - f0) ./ f0;
            dff = (dff - mean(dff)) ./ std(dff);
        end
        
        %% parse licks
        lick_times = event_times(lick_flags);
        lick_edges = event_times(1) : dt : event_times(end);
        lick_counts = histcounts(lick_times,lick_edges);
        lick_idcs = sum(lick_times > reward_times',2);
        lick_times_delivery = arrayfun(@(x)...
            lick_times(ismember(lick_idcs,x-[1,0])) - ...
            reward_times(x),reward_idcs,...
            'uniformoutput',false);
        lick_times_collection = arrayfun(@(x)...
            lick_times(ismember(lick_idcs,x-[1,0])) - ...
            firstlick_times(x),reward_idcs,...
            'uniformoutput',false);
        
        % get lick-aligned snippets of lick counts
        [lick_delivery_snippets,lick_delivery_time] = signal2eventsnippets(...
            lick_edges(1:end-1),lick_counts,reward_times,...
            meta.epochs.delivery + lickrate_kernel.paddx,dt);
        [lick_collection_snippets,lick_collection_time] = signal2eventsnippets(...
            lick_edges(1:end-1),lick_counts,firstlick_times,...
            meta.epochs.collection + lickrate_kernel.paddx,dt);
        
        %% contingency-related metrics 

        % compute lick -> reward intervals
        lri_idcs = sum(lick_times > firstlick_times',2);
        lri = arrayfun(@(x)...
            firstlick_times(x) - lick_times(ismember(lri_idcs,x-1)),...
            reward_idcs,...
            'uniformoutput',false);
        
        % compute random time -> reward intervals
        random_times = sort(unifrnd(...
            event_times(1),event_times(end),sum(lick_flags),1));
        tri_idcs = sum(random_times > firstlick_times',2);
        tri = arrayfun(@(x)...
            firstlick_times(x) - random_times(ismember(tri_idcs,x-1)),...
            reward_idcs,...
            'uniformoutput',false);
        
        %% compute inter-lick-intervals (ILI)
        ili_events = diff([nan;lick_times]);
        ili_rewards = arrayfun(@(x)...
            ili_events(lick_idcs == x),reward_idcs,...
            'uniformoutput',false);
        
        %% parse photometry data
        
        % correct for nonstationary sampling frequency
        time = T(1) : dt : T(end);
        da = interp1(T,dff,time);
        
        % get event-aligned snippets of DA
        [da_baseline_snippets,da_baseline_time] = signal2eventsnippets(...
            time,da,firstlick_times,meta.epochs.baseline,dt);
        [da_reward_snippets,da_reward_time] = signal2eventsnippets(...
            time,da,firstlick_times,meta.epochs.reward,dt);
        [da_delivery_snippets,da_delivery_time] = signal2eventsnippets(...
            time,da,reward_times,meta.epochs.delivery,dt);
        [da_collection_snippets,da_collection_time] = signal2eventsnippets(...
            time,da,firstlick_times,meta.epochs.collection,dt);
        
        % preallocation
        da_reward_response = nan(n_rewards,1);
        
        % iterate through rewards
        for ii = 1 : n_rewards
            
            % compute 'DA response' metric
            da_reward_response(ii) = ...
                sum(da_reward_snippets(ii,:) * dt) / range(meta.epochs.reward) - ...
                sum(da_baseline_snippets(ii,:) * dt) / range(meta.epochs.baseline);
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
        
        % construct lick counts table
        lick_counts_table = table(...
            lick_delivery_snippets,...
            lick_collection_snippets,...
            'variablenames',{...
            'delivery',...
            'collection'});
        
        % construct lick times table
        lick_times_table = table(...
            lick_times_delivery,...
            lick_times_collection,...
            'variablenames',{...
            'delivery',...
            'collection'});
        
        % construct lick table
        lick_table = table(...
            lick_counts_table,...
            lick_times_table,...
            'variablenames',{...
            'count',...
            'time'});
        
        % contingency table
        contingency_table = table(...
            lri,...
            tri,...
            'variablenames',{...
            'lri',...
            'tri'});
        
        % construct DA table
        da_table = table(...
            da_delivery_snippets,...
            da_collection_snippets,...
            da_reward_response,...
            'variablenames',{...
            'delivery',...
            'collection',...
            'response'});
        
        % concatenate into a session table
        session_data = table(...
            categorical(cellstr(repmat(meta.mice.ids{mm},n_rewards,1)),meta.mice.ids),...
            repmat(ss,n_rewards,1),...
            reward_table,...
            iri_table,...
            reaction_times,...
            lick_table,...
            ili_rewards,...
            contingency_table,...
            da_table,...
            'variablenames',{...
            'mouse',...
            'session',...
            'reward'...
            'iri',...
            'rt',...
            'lick',...
            'ili',...
            'contingency',...
            'da',...
            });
        
        % increment mouse counters
        mouse_reward_counter = mouse_reward_counter + n_rewards;
        
        % append to the current mouse's table
        if ss == 1
            mouse_data = session_data;
            reaction_times_cell{mm} = reaction_times;
            lick_times_cell{mm} = lick_times;
        else
            mouse_data = [mouse_data; session_data];
            reaction_times_cell{mm} = ...
                [reaction_times_cell{mm}; reaction_times];
            lick_times_cell{mm} = ...
                [lick_times_cell{mm}; lick_times];
        end
    end
    
    % append to the final data table
    if mm == 1
        data = mouse_data;
    else
        data = [data; mouse_data];
    end
end

%% save data
if want2savedata
    experiment_file = fullfile(experiments_path,'randomrewards.mat');
    save(experiment_file,...
        'meta','data','reaction_times_cell','lick_times_cell','-v7.3');
end