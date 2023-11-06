%% experiment II: classical conditioning
% description goes here

%% initialization
Jeong2022_preface;

%% used fixed random seed
rng(0);

%% key assumptions
use_clicks = 0;
use_cs_offset = 0;

%% experiment parameters
pre_cs_delay = 1.5;
cs_dur_set = 2;
n_cs_durs = numel(cs_dur_set);
trace_dur = 1;
iti_delay = 3;
iti_mu = 30;
iti_max = 90;

%% analysis parameters
baseline_period = [-1,0];
early_period = [0,1];
late_period = [-1,0] + cs_dur_set(1) + trace_dur;
normalization_window_length = 50;
subtraction_window_length = 100;

%% simulation parameters
n_trials_per_run = 100;
n_runs = 14;
n_trials = n_trials_per_run * n_runs;
trial_idcs = (1 : n_trials)';

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
n_bins = round(max(iti) / iti_mu) * 10;
iti_edges = linspace(0,max(iti),n_bins);
iti_counts = histcounts(iti,iti_edges);
iti_counts = iti_counts ./ nansum(iti_counts);
iti_pdf = pdf(iti_pd,iti_edges);
iti_pdf = iti_pdf ./ nansum(iti_pdf);

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
cs_onset_times = trial_onset_times + pre_cs_delay;
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
n_clicks = sum(click_counts);

%% reaction times
reaction_times = repmat(.5,n_trials,1);
% reaction_times = linspace(1,.1,n_trials)';
reaction_times = max(reaction_times,dt*2);
if ~use_clicks
    reaction_times = 0;
end

%% reward times
reward_times = click_times + reaction_times;
reward_times = dt * round(reward_times / dt);
reward_counts = histcounts(reward_times,state_edges);
n_rewards = sum(reward_counts);
reward_idcs = (1 : n_rewards)';

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
[state,value,rpe,exp2_weights] = tdlambda(...
    time,[],stimulus_times,reward_times,microstimuli,[],...
    'alpha',alpha,...
    'gamma',gamma,...
    'lambda',lambda);
% [state,value,rpe,rwdrate,exp2_weights] = difftdlambda(...
%     time,[],stimulus_times,reward_times,microstimuli,[],...
%     'alpha',alpha,...
%     'gamma',gamma,...
%     'lambda',lambda);

%% compute 'DA signal'
padded_rpe = padarray(rpe,dlight_kernel.nbins/2,0);
if use_dlight_kernel
    da = conv(padded_rpe(1:end-1),dlight_kernel.pdf,'valid');
else
    da = rpe;
end
da = da + psi * max(dlight_kernel.pdf);

%% get reward-aligned snippets of DA signal
[da_baseline_snippets,da_baseline_time] = ...
    signal2eventsnippets(time,da,cs_onset_times,baseline_period,dt);
[da_early_snippets,da_early_time] = ...
    signal2eventsnippets(time,da,cs_onset_times,early_period,dt);
[da_late_snippets,da_late_time] = ...
    signal2eventsnippets(time,da,cs_onset_times,late_period,dt);

%% compute 'DA response' metric

% preallocation
da_early_response = nan(n_trials,1);
da_late_response = nan(n_trials,1);

% iterate through trials
for ii = 1 : n_trials
    da_early_response(ii) = ...
        sum(da_early_snippets(ii,:)) - sum(da_baseline_snippets(ii,:));
    da_late_response(ii) = ...
        sum(da_late_snippets(ii,:)) - sum(da_baseline_snippets(ii,:));
end

%% reshape from trial-less time series to STATES x TRIALS x RUNS tensors

% preallocation
stimulus_tensor = nan(n_states_per_trial,n_trials_per_run,n_runs);
value_tensor = nan(n_states_per_trial,n_trials_per_run,n_runs);
rpe_tensor = nan(n_states_per_trial,n_trials_per_run,n_runs);
da_tensor = nan(n_states_per_trial,n_trials_per_run,n_runs);

% iterate through runs
for ii = 1 : n_runs
    
    % iterate through trials
    for jj = 1 : n_trials_per_run
        trial_idx = jj + (ii - 1) * n_trials_per_run;
        onset_idx = find(time >= trial_onset_times(trial_idx),1);
        if trial_idx < n_trials
            offset_idx = find(time >= trial_onset_times(trial_idx+1),1);
        else
            offset_idx = find(time >= trial_onset_times(trial_idx) + trial_dur(trial_idx),1);
        end
        idcs = onset_idx : offset_idx - 1;
        n_idcs = numel(idcs);
        stimulus_tensor(1:n_idcs,jj,ii) = ...
            cs_plus_onset_counts(idcs) + ...
            cs_minus_onset_counts(idcs) + ...
            cs_plus_offset_counts(idcs) * use_cs_offset + ...
            cs_minus_offset_counts(idcs) * use_cs_offset + ...
            click_counts(idcs) * use_clicks + ...
            reward_counts(idcs);
        value_tensor(1:n_idcs,jj,ii) = value(idcs);
        rpe_tensor(1:n_idcs,jj,ii) = rpe(idcs);
        da_tensor(1:n_idcs,jj,ii) = da(idcs);
    end
end

%% reshape from trial-less time series to STATES x TRIALS matrices

% preallocation
stimulus_matrix = nan(n_states_per_trial,n_trials);
value_matrix = nan(n_states_per_trial,n_trials);
rpe_matrix = nan(n_states_per_trial,n_trials);
da_matrix = nan(n_states_per_trial,n_trials);

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
end

%% figure 2: experiment II - test 3

% figure initialization
figure(figopt,...
    'name','experiment II: test 3');

% axes initialization
n_rows = 5;
n_cols = n_runs;
sp_cstype = subplot(n_rows,n_cols,1);
sp_state = subplot(n_rows,n_cols,2:n_cols-2);
sp_iti = subplot(n_rows,n_cols,n_cols-1:n_cols);
sp_da_mu = gobjects(1,n_runs);
sp_da = gobjects(1,n_runs);
sp_value_mu = gobjects(1,n_runs);
sp_value = gobjects(1,n_runs);
for ii = 1 : n_runs
    sp_da_mu(ii) = subplot(n_rows,n_cols,ii+n_cols*1);
    sp_da(ii) = subplot(n_rows,n_cols,ii+n_cols*2);
    sp_value_mu(ii) = subplot(n_rows,n_cols,ii+n_cols*3);
    sp_value(ii) = subplot(n_rows,n_cols,ii+n_cols*4);
end

% concatenate axes
sps_stages = [...
    sp_da_mu;...
    sp_da;...
    sp_value_mu;...
    sp_value;...
    ];
sps = [...
    sp_cstype;...
    sp_state;...
    sp_iti;...
    sps_stages(:);...
    ];

% axes settings
arrayfun(@(ax)set(ax.XAxis,'exponent',0),sps);
set(sps,axesopt);
set(sps_stages,...
    'xlim',[-pre_cs_delay,unique(trial_dur)+iti_delay]);
set(sps_stages(:,2:end),...
    'ytick',[],...
    'ycolor','none');
set(sp_cstype,...
    'xlim',[0,1]+[-1,1],...
    'xtick',[0,1],...
    'xticklabel',cs_set);
set(sp_state,...
    'ticklength',axesopt.ticklength/n_cols);
set([sp_state,sp_iti],...
    'ytick',[]);

% axes titles
title(sp_da_mu(1),'Early in training');
title(sp_da_mu(end),'Late in training');

% axes labels
ylabel(sp_cstype,'Count');
xlabel(sp_state,'Time (s)');
ylabel(sp_state,'State feature #');
xlabel(sp_iti,'ITI (s)');
ylabel(sp_iti,'PDF');
arrayfun(@(ax)xlabel(ax,'Time (s)'),[sp_da_mu;sp_da]);
arrayfun(@(ax)ylabel(ax,'DA (a.u.)'),[sp_da_mu;sp_da]);
arrayfun(@(ax)xlabel(ax,'Time (s)'),[sp_value_mu;sp_value]);
arrayfun(@(ax)ylabel(ax,'Value (a.u.)'),[sp_value_mu;sp_value]);

% plot CS distribution
patch(sp_cstype,...
    0+[-1,1,1,-1]*1/4,[0,0,1,1]*sum(~cs_plus_flags),cs_minus_clr,...
    'edgecolor',cs_minus_clr,...
    'linewidth',1.5,...
    'facealpha',2/3);
patch(sp_cstype,...
    1+[-1,1,1,-1]*1/4,[0,0,1,1]*sum(cs_plus_flags),cs_plus_clr,...
    'edgecolor',cs_plus_clr,...
    'linewidth',1.5,...
    'facealpha',2/3);

% plot state features
n_trials2plot = 15;
time_flags = ...
    time >= trial_onset_times(1) & ...
    time < trial_onset_times(n_trials2plot + 1);
imagesc(sp_state,...
    time(time_flags)+dt/2,[],state(time_flags,:)');

% plot ITI distribution
stem(sp_iti,iti_mu,max([iti_counts,iti_pdf]),...
    'color','k',...
    'marker','v',...
    'markersize',10,...
    'markerfacecolor','k',...
    'markeredgecolor','none',...
    'linewidth',2);
histogram(sp_iti,...
    'binedges',iti_edges,...
    'bincounts',iti_counts,...
    'facecolor','w',...
    'edgecolor','k',...
    'facealpha',1,...
    'linewidth',1);
plot(sp_iti,iti_edges,iti_pdf,...
    'color','k',...
    'linewidth',2);

% iterate through runs
for ii = 1 : n_runs
    run_idcs = (1 : n_trials_per_run) + (ii - 1) * n_trials_per_run;
    [~,sorted_idcs] = sortrows(cs(run_idcs));
    
    % plot DA trace
    clim = quantile(da_tensor,[0,1],'all')';
    imagesc(sp_da(ii),...
        [trial_time(1),trial_time(end)],[],...
        da_tensor(:,sorted_idcs,ii)',clim);
    
    % plot value trace
    clim = quantile(value_tensor,[0,1],'all')';
    imagesc(sp_value(ii),...
        [trial_time(1),trial_time(end)],[],...
        value_tensor(:,sorted_idcs,ii)',clim);
    
    % compute & plot average DA conditioned on CS
    da_minus_mu = nanmean(da_tensor(:,~cs_plus_flags(run_idcs),ii),2);
    plot(sp_da_mu(ii),trial_time,da_minus_mu,...
        'color',cs_minus_clr,...
        'linewidth',1);
    da_plus_mu = nanmean(da_tensor(:,cs_plus_flags(run_idcs),ii),2);
    plot(sp_da_mu(ii),trial_time,da_plus_mu,...
        'color',cs_plus_clr,...
        'linewidth',1);
    %         rpe_mu = nanmean(rpe_tensor(:,cs_flags,ii),2);
    %         plot(sp_da_mu(ii),trial_time,rpe_mu,...
    %             'color',cs_clrs(jj,:),...
    %             'linewidth',1);
    
    % compute & plot average value conditioned on CS
    value_minus_mu = nanmean(value_tensor(:,~cs_plus_flags(run_idcs),ii),2);
    plot(sp_value_mu(ii),trial_time,value_minus_mu,...
        'color',cs_minus_clr,...
        'linewidth',1);
    value_plus_mu = nanmean(value_tensor(:,cs_plus_flags(run_idcs),ii),2);
    plot(sp_value_mu(ii),trial_time,value_plus_mu,...
        'color',cs_plus_clr,...
        'linewidth',1);
end

% legend
[leg,icons] = legend(sp_da_mu(1),cs_set,...
    'location','northeast',...
    'box','off',...
    'autoupdate','off');
icons(3).XData = icons(3).XData + [1,0] * .3;
icons(5).XData = icons(5).XData + [1,0] * .3;

% axes linkage
arrayfun(@(ax1,ax2,ax3,ax4)linkaxes([ax1,ax2,ax3,ax4],'x'),...
    sp_da_mu,sp_da,sp_value_mu,sp_value);
linkaxes(sp_da_mu,'y');
linkaxes(sp_value_mu,'y');

% iterate through runs
for ii = 1 : n_runs
    
    % plot CS onset
    plot(sp_da_mu(ii),[0,0],ylim(sp_da_mu(ii)),...
        'color','k',...
        'linestyle','--',...
        'linewidth',1);
    plot(sp_value_mu(ii),[0,0],ylim(sp_value_mu(ii)),...
        'color','k',...
        'linestyle','--',...
        'linewidth',1);
    
    % plot CS offset
    if use_cs_offset
        plot(sp_da_mu(ii),[0,0]+unique(cs_dur),ylim(sp_da_mu(ii)),...
            'color','k',...
            'linestyle','--',...
            'linewidth',1);
        plot(sp_value_mu(ii),[0,0]+unique(cs_dur),ylim(sp_value_mu(ii)),...
            'color','k',...
            'linestyle','--',...
            'linewidth',1);
    end
    
    % plot offset of the trace period
    plot(sp_da_mu(ii),[0,0]+unique(cs_dur)+trace_dur,ylim(sp_da_mu(ii)),...
        'color','k',...
        'linestyle','--',...
        'linewidth',1);
    plot(sp_value_mu(ii),[0,0]+unique(cs_dur)+trace_dur,ylim(sp_value_mu(ii)),...
        'color','k',...
        'linestyle','--',...
        'linewidth',1);
end

% annotate model parameters
annotateModelParameters;

%% figure 3: experiment II - test 9

% figure initialization
figure(figopt,...
    'name','experiment II: test 9');

% axes initialization
n_rows = 4;
n_cols = 5;
sp_state = subplot(n_rows,n_cols,3:n_cols);
sp_da_mu = subplot(n_rows,n_cols,(1:2)+n_cols*0);
sp_da = subplot(n_rows,n_cols,(1:2)+n_cols*1);
sp_value_mu = subplot(n_rows,n_cols,(1:2)+n_cols*2);
sp_value = subplot(n_rows,n_cols,(1:2)+n_cols*3);
sp_baseline = subplot(n_rows,n_cols,3+n_cols*1);
sp_early = subplot(n_rows,n_cols,4+n_cols*1);
sp_late = subplot(n_rows,n_cols,5+n_cols*1);
sp_earlyresponse = subplot(n_rows,n_cols,3+n_cols*2);
sp_lateresponse = subplot(n_rows,n_cols,3+n_cols*3);
sp_test9_backpropagation = subplot(n_rows,n_cols,4+n_cols*[2,3]);
sp_test9_initialdynamics = subplot(n_rows,n_cols,5+n_cols*[2,3]);

% concatenate axes
sps = [...
    sp_state;...
    sp_da_mu;...
    sp_da;...
    sp_value_mu;...
    sp_value;...
    sp_baseline;...
    sp_early;...
    sp_late;...
    sp_earlyresponse;...
    sp_lateresponse;...
    sp_test9_backpropagation;...
    sp_test9_initialdynamics;...
    ];

% axes settings
arrayfun(@(ax)set(ax.XAxis,'exponent',0),sps);
set(sps,axesopt);
set([sp_da_mu,sp_da,sp_value_mu,sp_value],...
    'xlim',[-pre_cs_delay,max(trial_dur)+iti_delay]);
set(sp_state,...
    'ticklength',axesopt.ticklength/n_cols);
set(sp_baseline,...
    'xlim',baseline_period);
set(sp_early,...
    'xlim',early_period);
set(sp_late,...
    'xlim',late_period);
set([sp_early,sp_late],...
    'ycolor','none');
set(sp_test9_backpropagation,...
    'xlim',[1,n_rewards]+[-1,1]*.05*n_rewards,...
    'ylim',[-1,2],...
    'ytick',-1:2);
set(sp_test9_initialdynamics,...
    'xlim',[1,subtraction_window_length],...
    'ylim',[-1,1]*.2,...
    'ytick',-.2:.1:.2);

% axes titles
title(sp_baseline,'Baseline period');
title(sp_early,'Early period');
title(sp_late,'Late period');
title(sp_test9_backpropagation,'Test IX: backpropagation');
title(sp_test9_initialdynamics,'Test IX: <initial dynamics>');

% axes labels
xlabel(sp_state,'Time (s)');
ylabel(sp_state,'State feature #');
arrayfun(@(ax)xlabel(ax,'Time (s)'),[sp_da_mu;sp_da;sp_value_mu;sp_value]);
ylabel(sp_da_mu,'DA (a.u.)');
ylabel(sp_da,'Trial #');
xlabel(sp_late,'Trial #');
ylabel(sp_late,'DA response at US');
ylabel(sp_value_mu,'Value (a.u.)');
ylabel(sp_value,'Trial #');
xlabel(sp_baseline,'Time relative to CS (s)');
ylabel(sp_baseline,'DA (a.u.)');
xlabel(sp_early,'Time relative to CS (s)');
ylabel(sp_early,'DA (a.u.)');
xlabel(sp_late,'Time relative to CS (s)');
ylabel(sp_late,'DA (a.u.)');
xlabel(sp_earlyresponse,'Reward #');
ylabel(sp_earlyresponse,'DA early response (a.u.)');
xlabel(sp_lateresponse,'Reward #');
ylabel(sp_lateresponse,'DA late response (a.u.)');
xlabel(sp_test9_backpropagation,'Reward #');
ylabel(sp_test9_backpropagation,{'Normalized DA response',...
    sprintf('(1 = early response averaged over the last %i trials)',...
    normalization_window_length)});
xlabel(sp_test9_initialdynamics,...
    sprintf('Trial %i-%i',...
    min(xlim(sp_test9_initialdynamics)),...
    max(xlim(sp_test9_initialdynamics))));
ylabel(sp_test9_initialdynamics,...
    {'\DeltaNormalized DA response','(late - early)'});

% plot state features
n_trials2plot = 15;
time_flags = ...
    time >= trial_onset_times(1) & ...
    time < trial_onset_times(n_trials2plot + 1);
imagesc(sp_state,...
    time(time_flags)+dt/2,[],state(time_flags,:)');

% sort trials based on CS type
[~,sorted_idcs] = sortrows(cs);

% plot DA trace
clim = quantile(da_matrix,[0,1],'all')';
imagesc(sp_da,...
    [trial_time(1),trial_time(end)],[],...
    da_matrix(:,sorted_idcs)',clim);

% plot value trace
clim = quantile(value_matrix,[0,1],'all')';
imagesc(sp_value,...
    [trial_time(1),trial_time(end)],[],...
    value_matrix(:,sorted_idcs)',clim);

% compute & plot average DA conditioned on CS
da_minus_mu = nanmean(da_matrix(:,~cs_plus_flags),2);
plot(sp_da_mu,trial_time,da_minus_mu,...
    'color',cs_minus_clr,...
    'linewidth',1);
da_plus_mu = nanmean(da_matrix(:,cs_plus_flags),2);
plot(sp_da_mu,trial_time,da_plus_mu,...
    'color',cs_plus_clr,...
    'linewidth',1);

% compute & plot average value conditioned on CS
value_minus_mu = nanmean(value_matrix(:,~cs_plus_flags),2);
plot(sp_value_mu,trial_time,value_minus_mu,...
    'color',cs_minus_clr,...
    'linewidth',1);
value_plus_mu = nanmean(value_matrix(:,cs_plus_flags),2);
plot(sp_value_mu,trial_time,value_plus_mu,...
    'color',cs_plus_clr,...
    'linewidth',1);

% legend
legend(sp_da_mu,...
    {'CS+','CS-'},...
    'location','northeast',...
    'box','off',...
    'autoupdate','off');

% plot response windows used to compute DA responses
yylim = ylim(sp_da_mu);
yymax = max(yylim) * 1.1;
patch(sp_da_mu,...
    [baseline_period,fliplr(baseline_period)],...
    [-1,-1,1,1]*range(yylim)*.02+yymax,'w',...
    'edgecolor','k',...
    'facealpha',1,...
    'linewidth',1);
patch(sp_da_mu,...
    [early_period,fliplr(early_period)],...
    [-1,-1,1,1]*range(yylim)*.02+yymax,'k',...
    'edgecolor','k',...
    'facealpha',1,...
    'linewidth',1);
patch(sp_da_mu,...
    [late_period,fliplr(late_period)],...
    [-1,-1,1,1]*range(yylim)*.02+yymax,'k',...
    'edgecolor','k',...
    'facealpha',1,...
    'linewidth',1);
text(sp_da_mu,...
    mean(baseline_period),yymax*1.05,'bsl.',...
    'color','k',...
    'horizontalalignment','center',...
    'verticalalignment','bottom');
text(sp_da_mu,...
    mean(early_period),yymax*1.05,'early',...
    'color','k',...
    'horizontalalignment','center',...
    'verticalalignment','bottom');
text(sp_da_mu,...
    mean(late_period),yymax*1.05,'late',...
    'color','k',...
    'horizontalalignment','center',...
    'verticalalignment','bottom');

% plot average CS-aligned baseline signal
plot(sp_baseline,baseline_period,[0,0],':k');
da_baseline_mu = nanmean(da_baseline_snippets(~cs_plus_flags,:));
da_baseline_sig = nanstd(da_baseline_snippets(~cs_plus_flags,:));
da_baseline_sem = da_baseline_sig ./ sqrt(n_rewards);
errorpatch(da_baseline_time,...
    da_baseline_mu,da_baseline_sem,cs_minus_clr,...
    'edgecolor','none',...
    'facealpha',.25,...
    'parent',sp_baseline);
plot(sp_baseline,...
    da_baseline_time,da_baseline_mu,...
    'color',cs_minus_clr,...
    'linestyle','-',...
    'linewidth',1.5);
da_baseline_mu = nanmean(da_baseline_snippets(cs_plus_flags,:));
da_baseline_sig = nanstd(da_baseline_snippets(cs_plus_flags,:));
da_baseline_sem = da_baseline_sig ./ sqrt(n_rewards);
errorpatch(da_baseline_time,...
    da_baseline_mu,da_baseline_sem,cs_plus_clr,...
    'edgecolor','none',...
    'facealpha',.25,...
    'parent',sp_baseline);
plot(sp_baseline,...
    da_baseline_time,da_baseline_mu,...
    'color',cs_plus_clr,...
    'linestyle','-',...
    'linewidth',1.5);

% plot average CS-aligned early signal
plot(sp_early,early_period,[0,0],':k');
da_early_mu = nanmean(da_early_snippets(~cs_plus_flags,:));
da_early_sig = nanstd(da_early_snippets(~cs_plus_flags,:));
da_early_sem = da_early_sig ./ sqrt(n_rewards);
errorpatch(da_early_time,...
    da_early_mu,da_early_sem,cs_minus_clr,...
    'edgecolor','none',...
    'facealpha',.25,...
    'parent',sp_early);
plot(sp_early,...
    da_early_time,da_early_mu,...
    'color',cs_minus_clr,...
    'linewidth',1.5);
da_early_mu = nanmean(da_early_snippets(cs_plus_flags,:));
da_early_sig = nanstd(da_early_snippets(cs_plus_flags,:));
da_early_sem = da_early_sig ./ sqrt(n_rewards);
errorpatch(da_early_time,...
    da_early_mu,da_early_sem,cs_plus_clr,...
    'edgecolor','none',...
    'facealpha',.25,...
    'parent',sp_early);
plot(sp_early,...
    da_early_time,da_early_mu,...
    'color',cs_plus_clr,...
    'linewidth',1.5);

% plot average reward-aligned late signal
plot(sp_late,late_period,[0,0],':k');
da_late_mu = nanmean(da_late_snippets(~cs_plus_flags,:));
da_late_sig = nanstd(da_late_snippets(~cs_plus_flags,:));
da_late_sem = da_late_sig ./ sqrt(n_rewards);
errorpatch(da_late_time,...
    da_late_mu,da_late_sem,cs_minus_clr,...
    'edgecolor','none',...
    'facealpha',.25,...
    'parent',sp_late);
plot(sp_late,...
    da_late_time,da_late_mu,...
    'color',cs_minus_clr,...
    'linewidth',1.5);
da_late_mu = nanmean(da_late_snippets(cs_plus_flags,:));
da_late_sig = nanstd(da_late_snippets(cs_plus_flags,:));
da_late_sem = da_late_sig ./ sqrt(n_rewards);
errorpatch(da_late_time,...
    da_late_mu,da_late_sem,cs_plus_clr,...
    'edgecolor','none',...
    'facealpha',.25,...
    'parent',sp_late);
plot(sp_late,...
    da_late_time,da_late_mu,...
    'color',cs_plus_clr,...
    'linewidth',1.5);

% plot early DA response
scatter(sp_earlyresponse,...
    trial_idcs(~cs_plus_flags),da_early_response(~cs_plus_flags),20,...
    'marker','o',...
    'markerfacealpha',.5,...
    'markerfacecolor',cs_minus_clr,...
    'markeredgecolor',cs_minus_clr,...
    'linewidth',1);
scatter(sp_earlyresponse,...
    trial_idcs(cs_plus_flags),da_early_response(cs_plus_flags),20,...
    'marker','o',...
    'markerfacealpha',.5,...
    'markerfacecolor',cs_plus_clr,...
    'markeredgecolor',cs_plus_clr,...
    'linewidth',1);
plot(sp_earlyresponse,xlim(sp_earlyresponse),[1,1]*0,':k');

% plot late DA response
scatter(sp_lateresponse,...
    trial_idcs(~cs_plus_flags),da_late_response(~cs_plus_flags),20,...
    'marker','o',...
    'markerfacealpha',.5,...
    'markerfacecolor',cs_minus_clr,...
    'markeredgecolor',cs_minus_clr,...
    'linewidth',1);
scatter(sp_lateresponse,...
    trial_idcs(cs_plus_flags),da_late_response(cs_plus_flags),20,...
    'marker','o',...
    'markerfacealpha',.5,...
    'markerfacecolor',cs_plus_clr,...
    'markeredgecolor',cs_plus_clr,...
    'linewidth',1);
plot(sp_lateresponse,xlim(sp_lateresponse),[1,1]*0,':k');

% test 9: backpropagation of DA signals during learning (ratio)
da_early_plus_response = da_early_response(cs_plus_flags);
normalization_term = nanmean(...
    da_early_plus_response(end - normalization_window_length + 1 : end));
plot(sp_test9_backpropagation,[1,n_rewards],[0,0],':k',...
    'handlevisibility','off');
plot(sp_test9_backpropagation,[1,n_rewards],[1,1],':k',...
    'handlevisibility','off');
scatter(sp_test9_backpropagation,...
    reward_idcs,...
    da_early_response(cs_plus_flags)/normalization_term,20,...
    'marker','o',...
    'markerfacealpha',.5,...
    'markerfacecolor','k',...
    'markeredgecolor','k',...
    'linewidth',1);
scatter(sp_test9_backpropagation,...
    reward_idcs,...
    da_late_response(cs_plus_flags)/normalization_term,20,...
    'marker','o',...
    'markerfacealpha',.5,...
    'markerfacecolor',highlight_clr,...
    'markeredgecolor',highlight_clr,...
    'linewidth',1);
xxlim = xlim(sp_test9_initialdynamics);
yylim = ylim(sp_test9_backpropagation);
patch(sp_test9_backpropagation,...
    [xxlim,fliplr(xxlim)],...
    [-1,-1,1,1]*range(yylim)*.01+1.5,'k',...
    'edgecolor','k',...
    'facealpha',1,...
    'linewidth',1);
text(sp_test9_backpropagation,...
    mean(xxlim),1.55,'initial',...
    'color','k',...
    'horizontalalignment','center',...
    'verticalalignment','bottom');

% test 9: backpropagation of DA signals during learning (difference)
plot(sp_test9_initialdynamics,[1,n_rewards],[0,0],':k',...
    'handlevisibility','off');
da_late_early_diff = ...
    da_late_response(cs_plus_flags) / normalization_term - ...
    da_early_response(cs_plus_flags) / normalization_term;
plot(sp_test9_initialdynamics,[1,n_rewards],[0,0],':k',...
    'handlevisibility','off');
patch(sp_test9_initialdynamics,...
    mean(xlim(sp_test9_initialdynamics))+...
    range(xlim(sp_test9_initialdynamics))*[-1,1,1,-1]*1/8,...
    [0,0,1,1]*nanmean(da_late_early_diff(1:subtraction_window_length)),...
    [1,1,1]*.75,...
    'edgecolor','k',...
    'linewidth',1.5,...
    'linestyle','-',...
    'facealpha',1);
plot(sp_test9_initialdynamics,...
    xlim(sp_test9_initialdynamics),[0,0],'-k',...
    'linewidth',axesopt.linewidth);

% legend
legend(sp_test9_backpropagation,...
    {'early','late'},...
    'location','southwest',...
    'box','off',...
    'autoupdate','off');

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
linkaxes([sp_baseline,sp_early,sp_late],'y');
linkaxes([sp_earlyresponse,sp_lateresponse],'y');

% annotate model parameters
annotateModelParameters;