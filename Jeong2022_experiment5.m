%% experiment V: classical conditioning - background rewards
% description goes here

%% initialization
if ~exist('exp3_weights','var')
    Jeong2022_experiment3;
end

%% used fixed random seed
rng(0);

%% key assumptions
use_clicks = 0;
use_cs_offset = 1;

%% analysis parameters
cs_period = [0,2];
baseline_period = [-1,0];

%% experiment parameters
pre_cs_delay = 1;
cs_dur_set = 8;
n_cs_durs = numel(cs_dur_set);
trace_dur = 1;
iti_delay = 3;
iti_mu = 30;
iti_max = 90;

%% simulation parameters
n_trials = 500;
trial_idcs = 1 : n_trials;

%% conditioned stimuli (CS)
cs_dur = repmat(cs_dur_set(1),n_trials,1);
cs_plus_proportion = .5;
cs = categorical(rand(n_trials,1)<=cs_plus_proportion,[0,1],{'CS-','CS+'});
cs_set = categories(cs);
n_cs = numel(cs_set);
cs_plus_flags = cs == 'CS+';

%% trial time
trial_dur = pre_cs_delay + cs_dur + trace_dur + iti_delay;
max_trial_dur = max(trial_dur) + iti_max;
trial_time = (0 : dt : max_trial_dur - dt) - pre_cs_delay;
n_states_per_trial = numel(trial_time);
trial_state_edges = linspace(0,max_trial_dur,n_states_per_trial+1);

%% inter-trial-intervals
iti_pd = truncate(makedist('exponential','mu',iti_mu),0,iti_max);
iti = random(iti_pd,n_trials,1);
iti = dt * round(iti / dt);

%% inter-trial-onset-intervals
itoi = trial_dur + iti;

%% trial onset times
trial_onset_times = cumsum(itoi);
trial_onset_times = dt * round(trial_onset_times / dt);

%% simulation time
dur = trial_onset_times(end) + max_trial_dur;
time = 0 : dt : dur - dt;
n_states = numel(time);
state_edges = linspace(0,dur,n_states+1);

%% CS onset times
cs_plus_onset_times = trial_onset_times(cs_plus_flags) + pre_cs_delay;
cs_minus_onset_times = trial_onset_times(~cs_plus_flags) + pre_cs_delay;
cs_plus_onset_counts = histcounts(cs_plus_onset_times,state_edges);
cs_minus_onset_counts = histcounts(cs_minus_onset_times,state_edges);

%% CS offset times
cs_plus_offset_times = cs_plus_onset_times + cs_dur(cs_plus_flags);
cs_minus_offset_times = cs_minus_onset_times + cs_dur(~cs_plus_flags);
cs_plus_offset_counts = histcounts(cs_plus_offset_times,state_edges);
cs_minus_offset_counts = histcounts(cs_minus_offset_times,state_edges);

%% CS flags
cs_plus_ison = sum(...
    time >= cs_plus_onset_times & ...
    time <= cs_plus_offset_times,1)';
cs_minus_ison = sum(...
    time >= cs_minus_onset_times & ...
    time <= cs_minus_offset_times,1)';

%% click times
click_trial_times = nan(n_trials,1);
click_trial_times(cs_plus_flags) = pre_cs_delay + cs_dur(cs_plus_flags) + trace_dur;
click_times = click_trial_times + trial_onset_times;
click_times = dt * round(click_times / dt);
click_counts = histcounts(click_times,state_edges);
[~,click_state_idcs] = ...
    min(abs(time - click_times(cs_plus_flags)),[],2);
n_clicks = numel(click_state_idcs);

%% reaction times
reaction_times = repmat(.5,n_trials,1);
% reaction_times = linspace(1,.1,n_trials)';
reaction_times = max(reaction_times,dt*2);
if ~use_clicks
    reaction_times = 0;
end

%% background reward times
bg_iri_mu = 6;
bg_cs_min_delay = 6;
[~,bg_reward_times] = poissonprocess(1/bg_iri_mu,dur);
bg_reward_times = unique(dt * round(bg_reward_times / dt));
cs_onset_times = sort([cs_plus_onset_times;cs_minus_onset_times]);
cs_offset_times = sort([cs_plus_offset_times;cs_minus_offset_times]);
bg_reward_start_idx = floor(n_trials / 2) + 1;
bg_reward_flags = ...
    bg_reward_times >= cs_onset_times(bg_reward_start_idx) & ...
    bg_reward_times <= cs_onset_times(end) + max_trial_dur;
bg_reward_times(~bg_reward_flags) = nan;
for ii = 1 : n_trials
    violation_flags = ...
        abs(bg_reward_times - cs_onset_times(ii)) < bg_cs_min_delay | ...
        (bg_reward_times >= cs_onset_times(ii) & ...
        bg_reward_times <= cs_offset_times(ii) + trace_dur);
    bg_reward_times(violation_flags) = nan;
end
bg_reward_times = bg_reward_times(~isnan(bg_reward_times));
bg_reward_counts = histcounts(bg_reward_times,state_edges);
n_bg_rewards = numel(bg_reward_times);

%% background inter-reward-intervals
bg_iri = diff([0;bg_reward_times]);
n_bins = round(max(bg_iri) / bg_iri_mu) * 10;
bg_iri_edges = linspace(0,max(bg_iri),n_bins);
bg_iri_counts = histcounts(bg_iri,bg_iri_edges);
bg_iri_counts = bg_iri_counts ./ nansum(bg_iri_counts);
bg_iri_pdf = exppdf(bg_iri_edges,bg_iri_mu);
bg_iri_pdf = bg_iri_pdf ./ nansum(bg_iri_pdf);

%% reward times
reward_times = click_times + reaction_times;
reward_times = dt * round(reward_times / dt);
reward_counts = histcounts(reward_times,state_edges);
[~,reward_state_idcs] = ...
    min(abs(time - reward_times(cs_plus_flags)),[],2);
n_rewards = numel(reward_state_idcs);

% !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
reward_times = sort([reward_times;bg_reward_times]);

%% microstimuli
stimulus_trace = stimulustracefun(y0,tau,time)';
mus = linspace(1,0,n);
microstimuli = microstimulusfun(stimulus_trace,mus,sigma);

%% UNCOMMENT TO REPLACE MICROSTIMULI WITH COMPLETE SERIAL COMPOUND
% csc = zeros(n_states,n);
% pulse_duration = .5;
% pulse_length = floor(pulse_duration / dt);
% for ii = 1 : n
%     idcs = (1 : pulse_length) + (ii - 1) * pulse_length;
%     csc(idcs,ii) = 1;
% end
% microstimuli = csc;
% microstimuli = microstimuli / max(sum(microstimuli,2));

%% concatenate all stimulus times
stimulus_times = {...
    reward_times,...
    cs_plus_onset_times,...
    cs_minus_onset_times};
if use_clicks
    stimulus_times = [...
        stimulus_times,...
        click_times];
end
if use_cs_offset
    stimulus_times = [...
        stimulus_times,...
        cs_plus_offset_times,...
        cs_minus_offset_times];
end

%% concatenate all state flags
cs_flags = [...
    cs_plus_ison,...
    cs_minus_ison];

%% TD learning
[state,value,rpe,exp5_weights] = tdlambda(...
    time,[],stimulus_times,reward_times,microstimuli,exp3_weights,...
    'alpha',alpha,...
    'gamma',gamma,...
    'lambda',lambda);

%% compute 'DA signal'
padded_rpe = padarray(rpe,dlight_kernel.nbins/2,0);
da = conv(padded_rpe(1:end-1),dlight_kernel.pdf,'valid');
da = da / max(dlight_kernel.pdf);

%% get CS- & US-aligned snippets of DA signal
[da_cs_snippets,da_cs_time] = signal2eventsnippets(...
    time,da,cs_plus_onset_times,cs_period,dt);
[da_baseline_snippets,da_baseline_time] = signal2eventsnippets(...
    time,da,cs_plus_onset_times,baseline_period,dt);

%% compute 'DA response' metrics

% preallocation
da_cs_response = nan(n_rewards,1);

% iterate through rewards
for ii = 1 : n_rewards
    da_cs_response(ii) = ...
        sum(da_cs_snippets(ii,:)) - sum(da_baseline_snippets(ii,:));
end

%% reshape from trial-less time series to STATES x TRIALS matrices

% preallocation
stimulus_matrix = nan(n_states_per_trial,n_trials);
value_matrix = nan(n_states_per_trial,n_trials);
rpe_matrix = nan(n_states_per_trial,n_trials);
da_matrix = nan(n_states_per_trial,n_trials);
bg_reward_matrix = nan(n_states_per_trial,n_trials);

% iterate through trials
for ii = 1 : n_trials
    onset_idx = find(time >= trial_onset_times(ii),1);
    if ii < n_trials
        offset_idx = find(time >= trial_onset_times(ii+1),1);
    else
        offset_idx = find(time >= trial_onset_times(ii) + trial_dur(ii),1);
    end
    idcs = onset_idx : offset_idx - 1;
    n_idcs = numel(idcs);
    stimulus_matrix(1:n_idcs,ii) = ...
        cs_plus_onset_counts(idcs) + ...
        cs_minus_onset_counts(idcs) + ...
        cs_plus_offset_counts(idcs) * use_cs_offset + ...
        cs_minus_offset_counts(idcs) * use_cs_offset + ...
        click_counts(idcs) * use_clicks + ...
        reward_counts(idcs);
    value_matrix(1:n_idcs,ii) = value(idcs);
    rpe_matrix(1:n_idcs,ii) = rpe(idcs);
    da_matrix(1:n_idcs,ii) = da(idcs);
    bg_reward_matrix(1:n_idcs,ii) = bg_reward_counts(idcs);
end

%% compute training stage indices ('pre' & 'post' omission)
stage_divisor_idcs = floor([0,.5,1] * sum(cs_dur == cs_dur_set(1)));
n_stages = numel(stage_divisor_idcs) - 1;
stage_clrs = [.7,.7,.7; .1,.25,.65];

%% compute reward rate
total_reward_counts = reward_counts + bg_reward_counts;
rwdrate = conv(total_reward_counts/dt,rwdrate_kernel.pdf,'same');
rwdrate = rwdrate * 60;

%% figure 5: experiment V

% figure initialization
figure(figopt,...
    'name','experiment V: test 7');

% axes initialization
n_rows = 2 + 2;
n_cols = 4;
sp_da_mu = subplot(n_rows,n_cols,1+n_cols*0);
sp_da = subplot(n_rows,n_cols,1+n_cols*1);
sp_value_mu = subplot(n_rows,n_cols,1+n_cols*2);
sp_value = subplot(n_rows,n_cols,1+n_cols*3);
sp_bgiri = subplot(n_rows,n_cols,2+n_cols*0);
sp_rwdrate = subplot(n_rows,n_cols,2+n_cols*1);
sp_test7 = subplot(n_rows,n_cols,2+n_cols*[2,3]);

% concatenate axes
sps_stages = [...
    sp_da_mu;...
    sp_da;...
    sp_value_mu;...
    sp_value;...
    ];
sps = [...
    sps_stages(:);...
    sp_bgiri;...
    sp_rwdrate;...
    sp_test7;...
    ];

% axes settings
arrayfun(@(ax)set(ax.XAxis,'exponent',0),sps);
set(sps,axesopt);
set(sps_stages,...
    'xlim',[-pre_cs_delay,max(trial_dur)+iti_delay]);
set(sp_bgiri,...
    'xlim',[0,20]);
set(sp_test7,...
    'xlim',[0,1],...
    'ylim',[0,1],...
    'plotboxaspectratio',[1,1,1]);

% axes titles
title(sp_test7,'Test VII');

% axes labels
arrayfun(@(ax)xlabel(ax,'Time (s)'),[sp_da_mu;sp_da;sp_value_mu;sp_value]);
ylabel(sp_da_mu,'DA (a.u.)');
ylabel(sp_da,'Trial #');
ylabel(sp_value_mu,'Value (a.u.)');
ylabel(sp_value,'Trial #');
xlabel(sp_bgiri,'Background IRI (s)');
ylabel(sp_bgiri,'PDF');
xlabel(sp_rwdrate,'Time (s)');
ylabel(sp_rwdrate,'Rewards / minute');
xlabel(sp_test7,'Trial #');
ylabel(sp_test7,'DA response at CS');

% vertical offset for raster plots
offset = 0;

% iterate through stages
for ii = 1 : n_stages
    stage_idcs = stage_divisor_idcs(ii) + 1 : stage_divisor_idcs(ii+1);
    stage_flags = ismember(trial_idcs,stage_idcs)';
    
    % trial selection
    trial_flags = ...
        cs_plus_flags & ...
        stage_flags;
    n_flagged_trials = sum(trial_flags);
    
    % plot DA trace
    clim = quantile(da_matrix,[0,1],'all')';
    imagesc(sp_da,...
        [trial_time(1),trial_time(end)],[1,n_flagged_trials]+offset,...
        da_matrix(:,trial_flags)',clim);
    plot(sp_da,...
        [1,1]*0,[1,n_flagged_trials]+offset,...
        'color',stage_clrs(ii,:),...
        'linewidth',1,...
        'linestyle','-');
    plot(sp_da,...
        [1,1]*unique(cs_dur(trial_flags)),[1,n_flagged_trials]+offset,...
        'color',stage_clrs(ii,:),...
        'linewidth',1,...
        'linestyle','-');
    
    % plot value trace
    clim = quantile(value_matrix,[0,1],'all')';
    imagesc(sp_value,...
        [trial_time(1),trial_time(end)],[1,n_flagged_trials]+offset,...
        value_matrix(:,trial_flags)',clim);
    plot(sp_value,...
        [1,1]*0,[1,n_flagged_trials]+offset,...
        'color',stage_clrs(ii,:),...
        'linewidth',1,...
        'linestyle','-');
    plot(sp_value,...
        [1,1]*unique(cs_dur(trial_flags)),[1,n_flagged_trials]+offset,...
        'color',stage_clrs(ii,:),...
        'linewidth',1,...
        'linestyle','-');
    
    % plot background rewards
    flagged_onset_times = cs_onset_times(trial_flags);
    bg_reward_trials = sum(bg_reward_times > flagged_onset_times',2);
    bg_reward_flags = bg_reward_trials > 0;
    bg_reward_trials = bg_reward_trials(bg_reward_flags);
    bg_reward_trial_times = bg_reward_times(bg_reward_flags) - ...
        flagged_onset_times(bg_reward_trials);
    plot(sp_da,...
        bg_reward_trial_times,bg_reward_trials+offset,...
        'color','w',...
        'marker','.',...
        'markersize',5,...
        'linestyle','none');
    
    % compute & plot average DA conditioned on CS
    da_mu = nanmean(da_matrix(:,trial_flags),2);
    plot(sp_da_mu,trial_time,da_mu,...
        'color',stage_clrs(ii,:),...
        'linewidth',1);
    
    % compute & plot average value conditioned on CS
    value_mu = nanmean(value_matrix(:,trial_flags),2);
    plot(sp_value_mu,trial_time,value_mu,...
        'color',stage_clrs(ii,:),...
        'linewidth',1);
    
    % update vertical offset for raster plots
    offset = offset + n_flagged_trials;
end

% legend
legend(sp_da_mu,...
    {'w/o background','w/ background'},...
    'location','northeast',...
    'box','off',...
    'autoupdate','off');

% plot IRI distribution for background rewards
stem(sp_bgiri,bg_iri_mu,max([bg_iri_counts,bg_iri_pdf]),...
    'color','k',...
    'marker','v',...
    'markersize',10,...
    'markerfacecolor','k',...
    'markeredgecolor','none',...
    'linewidth',2);
histogram(sp_bgiri,...
    'binedges',bg_iri_edges,...
    'bincounts',bg_iri_counts,...
    'facecolor','w',...
    'edgecolor','k',...
    'facealpha',1,...
    'linewidth',1);
plot(sp_bgiri,bg_iri_edges,bg_iri_pdf,...
    'color','k',...
    'linewidth',2);

% plot overall reward rate
plot(sp_rwdrate,...
    time,rwdrate,...
    'color','k',...
    'linewidth',1);

% test 7: DA CS responses as a function of trial number
exp_start_idx = find(trial_idcs(cs_plus_flags) > bg_reward_start_idx,1);
plot(sp_test7,...
    (1:n_rewards)./n_rewards,cumsum(da_cs_response)/sum(da_cs_response),...
    'color','k',...
    'linewidth',1.5);
plot(sp_test7,...
    [1,1]*exp_start_idx./n_rewards,ylim(sp_test7),'--k');
plot(sp_test7,...
    [0,1],[0,1],'--k');
text(sp_test7,.25,.75,'decreases',...
    'color',[1,1,1]*.75,...
    'horizontalalignment','center',...
    'units','normalized');
text(sp_test7,.75,.25,'increases',...
    'color',[1,1,1]*.75,...
    'horizontalalignment','center',...
    'units','normalized');

% plot CS onset
plot(sp_da_mu,[0,0],ylim(sp_da_mu),...
    'color','k',...
    'linestyle','--',...
    'linewidth',1);
plot(sp_value_mu,[0,0],ylim(sp_value_mu),...
    'color','k',...
    'linestyle','--',...
    'linewidth',1);

% iterate through CS durations
for ii = 1 : n_cs_durs
    
    % plot CS offset
    if use_cs_offset
        plot(sp_da_mu,[0,0]+cs_dur_set(ii),ylim(sp_da_mu),...
            'color','k',...
            'linestyle','--',...
            'linewidth',1);
        plot(sp_value_mu,[0,0]+cs_dur_set(ii),ylim(sp_value_mu),...
            'color','k',...
            'linestyle','--',...
            'linewidth',1);
    end
    
    % plot offset of the trace period
    plot(sp_da_mu,[0,0]+cs_dur_set(ii)+trace_dur,ylim(sp_da_mu),...
        'color','k',...
        'linestyle','--',...
        'linewidth',1);
    plot(sp_value_mu,[0,0]+cs_dur_set(ii)+trace_dur,ylim(sp_value_mu),...
        'color','k',...
        'linestyle','--',...
        'linewidth',1);
end

% axes linkage
arrayfun(@(ax1,ax2,ax3,ax4)linkaxes([ax1,ax2,ax3,ax4],'x'),...
    sp_da_mu,sp_da,sp_value_mu,sp_value);

% annotate model parameters
annotateModelParameters;