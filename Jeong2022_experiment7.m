%% experiment VII: sequential conditioning
% description goes here

%% initialization
Jeong2022_preface;

%% used fixed random seed
rng(0);

%% key assumptions
use_clicks = 0;
use_cs_offset = 0;

%% experiment parameters
pre_cs1_delay = 1.5;
cs1_dur = 1;
cs2_dur = 1;
cs1cs2_interval = .5;
trace_dur = .5;
iti_delay = 0;
iti_mu = 60;
iti_max = 180;

%% analysis parameters
baseline_period = [-1,0];
cs1_period = [0,1];
cs2_period = cs1_period + cs1_dur + cs1cs2_interval;
us_period = cs2_period + cs2_dur + trace_dur;
normalization_window_length = 50;
subtraction_window_length = 50;

%% simulation parameters
n_trials = 200;
trial_idcs = 1 : n_trials;

%% trial time
trial_dur = pre_cs1_delay + cs1_dur + cs1cs2_interval + ...
    cs2_dur + trace_dur + iti_delay;
max_trial_dur = max(trial_dur) + iti_max;
trial_time = (0 : dt : max_trial_dur - dt) - pre_cs1_delay;
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

%% CS1 onset times
cs1_onset_times = trial_onset_times + pre_cs1_delay;
cs1_onset_counts = histcounts(cs1_onset_times,state_edges);

%% CS1 offset times
cs1_offset_times = cs1_onset_times + cs1_dur;
cs1_offset_counts = histcounts(cs1_offset_times,state_edges);

%% CS2 onset times
cs2_onset_times = cs1_offset_times + cs1cs2_interval;
cs2_onset_counts = histcounts(cs2_onset_times,state_edges);

%% CS2 offset times
cs2_offset_times = cs2_onset_times + cs2_dur;
cs2_offset_counts = histcounts(cs2_offset_times,state_edges);

%% CS flags
cs1_ison = sum(...
    time >= cs1_onset_times & ...
    time <= cs1_offset_times,1)';
cs2_ison = sum(...
    time >= cs2_onset_times & ...
    time <= cs2_offset_times,1)';

%% click times
click_trial_times = trial_dur - iti_delay;
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
    cs1_onset_times,...
    cs2_onset_times};
if use_clicks
    stimulus_times = [...
        stimulus_times,...
        click_times];
end
if use_cs_offset
    stimulus_times = [...
        stimulus_times,...
        cs1_offset_times,...
        cs2_offset_times];
end

%% concatenate all state flags
cs_flags = [...
    cs1_ison,...
    cs2_ison];

%% TD learning
[state,value,rpe,exp7_weights] = tdlambda(...
    time,[],stimulus_times,reward_times,microstimuli,[],...
    'alpha',alpha,...
    'gamma',gamma,...
    'lambda',lambda);
% [state,value,rpe,rwdrate,exp7_weights] = difftdlambda(...
%     time,[],stimulus_times,reward_times,microstimuli,[],...
%     'alpha',alpha,...
%     'gamma',gamma,...
%     'lambda',lambda);

%% compute 'DA signal'
padded_rpe = padarray(rpe,dlight_kernel.nbins/2,0);
da = conv(padded_rpe(1:end-1),dlight_kernel.pdf,'valid');

%% get CS- & US-aligned snippets of DA signal
[da_baseline_snippets,da_baseline_time] = signal2eventsnippets(...
    time,da,cs1_onset_times,baseline_period,dt);
[da_cs1_snippets,da_cs1_time] = signal2eventsnippets(...
    time,da,cs1_onset_times,cs1_period,dt);
[da_cs2_snippets,da_cs2_time] = signal2eventsnippets(...
    time,da,cs1_onset_times,cs2_period,dt);
[da_us_snippets,da_us_time] = signal2eventsnippets(...
    time,da,cs1_onset_times,us_period,dt);

%% compute 'DA response' metrics

% preallocation
da_cs1_response = nan(n_rewards,1);
da_cs2_response = nan(n_rewards,1);
da_us_response = nan(n_rewards,1);

% iterate through rewards
for ii = 1 : n_rewards
    da_cs1_response(ii) = ...
        sum(da_cs1_snippets(ii,:)) - sum(da_baseline_snippets(ii,:));
    da_cs2_response(ii) = ...
        sum(da_cs2_snippets(ii,:)) - sum(da_baseline_snippets(ii,:));
    da_us_response(ii) = ...
        sum(da_us_snippets(ii,:)) - sum(da_baseline_snippets(ii,:));
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
        offset_idx = find(time >= trial_onset_times(ii) + trial_dur,1);
    end
    idcs = onset_idx : offset_idx - 1;
    n_idcs = numel(idcs);
    stimulus_matrix(1:n_idcs,ii) = ...
        cs1_onset_counts(idcs) + ...
        cs2_onset_counts(idcs) + ...
        cs1_offset_counts(idcs) * use_cs_offset + ...
        cs2_offset_counts(idcs) * use_cs_offset + ...
        click_counts(idcs) * use_clicks + ...
        reward_counts(idcs);
    value_matrix(1:n_idcs,ii) = value(idcs);
    rpe_matrix(1:n_idcs,ii) = rpe(idcs);
    da_matrix(1:n_idcs,ii) = da(idcs);
end

%% compute reward rate
% rwdrate = conv(reward_counts/dt,rwdrate_kernel.pdf,'same');
rwdrate = rwdrate * 60;

%% figure 8: experiment VII

% figure initialization
figure(figopt,...
    'name','experiment VII: tests 10 & 11');

% axes initialization
n_rows = 4;
n_cols = 6;
sp_da_mu = subplot(n_rows,n_cols,[1,2]+n_cols*0);
sp_da = subplot(n_rows,n_cols,[1,2]+n_cols*1);
sp_value_mu = subplot(n_rows,n_cols,[1,2]+n_cols*2);
sp_value = subplot(n_rows,n_cols,[1,2]+n_cols*3);
sp_state = subplot(n_rows,n_cols,[3,4,5]+n_cols*0);
sp_iti = subplot(n_rows,n_cols,6+n_cols*0);
sp_baseline = subplot(n_rows,n_cols,3+n_cols*1);
sp_cs1 = subplot(n_rows,n_cols,4+n_cols*1);
sp_cs2 = subplot(n_rows,n_cols,5+n_cols*1);
sp_us = subplot(n_rows,n_cols,6+n_cols*1);
sp_csresponse = subplot(n_rows,n_cols,3+n_cols*2);
sp_usresponse = subplot(n_rows,n_cols,3+n_cols*3);
sp_test10_backpropagation = subplot(n_rows,n_cols,4+n_cols*[2,3]);
sp_test10_asymptoticdynamics = subplot(n_rows,n_cols,5+n_cols*[2,3]);
sp_test10_initialdynamics = subplot(n_rows,n_cols,6+n_cols*[2,3]);

% concatenate axes
sps = [...
    sp_da_mu;...
    sp_da;...
    sp_value_mu;...
    sp_value;...
    sp_state;...
    sp_iti;...
    sp_baseline;...
    sp_cs1;...
    sp_cs2;...
    sp_us;...
    sp_csresponse;...
    sp_usresponse;...
    sp_test10_backpropagation;...
    sp_test10_asymptoticdynamics;...
    sp_test10_initialdynamics;...
    ];

% axes settings
arrayfun(@(ax)set(ax.XAxis,'exponent',0),sps);
set(sps,axesopt);
set([sp_da_mu,sp_da,sp_value_mu,sp_value],...
    'xlim',[-pre_cs1_delay,max(trial_dur)+iti_delay]);
set(sp_state,...
    'ticklength',axesopt.ticklength/n_cols);
set(sp_iti,...
    'xlim',[0,iti_max]);
set(sp_baseline,...
    'xlim',baseline_period);
set(sp_cs1,...
    'xlim',cs1_period);
set(sp_cs2,...
    'xlim',cs2_period);
set(sp_us,...
    'xlim',us_period);
set(sp_usresponse,...
    'xlim',[1,n_rewards]);
set(sp_test10_backpropagation,...
    'xlim',[1,n_rewards]+[-1,1]*.05*n_rewards,...
    'xtick',[1,100:100:n_rewards],...
    'ylim',[-1,2],...
    'ytick',-1:2);
set(sp_test10_asymptoticdynamics,...
    'xlim',n_rewards+subtraction_window_length*[-1,0]+[1,0],...
    'ylim',ylim(sp_test10_backpropagation),...
    'ytick',yticks(sp_test10_backpropagation),...
    'ycolor','none');
set(sp_test10_initialdynamics,...
    'xlim',[1,subtraction_window_length],...
    'ylim',[-1,1]*.6,...
    'ytick',-.6:.2:.6);

% axes titles
title(sp_baseline,'Baseline period');
title(sp_cs1,'CS1 period');
title(sp_cs2,'CS2 period');
title(sp_us,'US period');
title(sp_test10_backpropagation,'Test X: backpropagation');
title(sp_test10_asymptoticdynamics,'Test X: <asymptotic dynamics>');
title(sp_test10_initialdynamics,'Test X: <initial dynamics>');

% axes labels
arrayfun(@(ax)xlabel(ax,'Time (s)'),[sp_da_mu;sp_da;sp_value_mu;sp_value]);
ylabel(sp_da_mu,'DA (a.u.)');
ylabel(sp_da,'Trial #');
xlabel(sp_us,'Time (s)');
ylabel(sp_value_mu,'Value (a.u.)');
ylabel(sp_value,'Trial #');
xlabel(sp_state,'Time (s)');
ylabel(sp_state,'State feature #');
xlabel(sp_iti,'ITI (s)');
ylabel(sp_iti,'PDF');
xlabel(sp_baseline,'Time relative to CS1 (s)');
ylabel(sp_baseline,'DA (a.u.)');
xlabel(sp_cs1,'Time relative to CS1 onset (s)');
ylabel(sp_cs1,'DA (a.u.)');
xlabel(sp_cs2,'Time relative to CS1 onset (s)');
ylabel(sp_cs2,'DA (a.u.)');
xlabel(sp_us,'Time relative to CS1 onset (s)');
ylabel(sp_us,'DA (a.u.)');
xlabel(sp_csresponse,'Trial #');
ylabel(sp_csresponse,'DA response at CSi');
xlabel(sp_usresponse,'Trial #');
ylabel(sp_usresponse,'DA response at US');
xlabel(sp_test10_backpropagation,'Reward #');
ylabel(sp_test10_backpropagation,{'Normalized DA response',...
    sprintf('(1 = CS1 response averaged over the last %i trials)',...
    normalization_window_length)});
xlabel(sp_test10_asymptoticdynamics,...
    sprintf('Trial %i-%i',...
    min(xlim(sp_test10_asymptoticdynamics)),...
    max(xlim(sp_test10_asymptoticdynamics))));
ylabel(sp_test10_asymptoticdynamics,...
    {'\DeltaNormalized DA response','(CS2 - CS1)'});
xlabel(sp_test10_initialdynamics,...
    sprintf('Trial %i-%i',...
    min(xlim(sp_test10_initialdynamics)),...
    max(xlim(sp_test10_initialdynamics))));
ylabel(sp_test10_initialdynamics,...
    {'\DeltaNormalized DA response','(CS2 - CS1)'});

% plot state features
n_trials2plot = 15;
time_flags = ...
    time >= trial_onset_times(1) & ...
    time < trial_onset_times(n_trials2plot + 1);
imagesc(sp_state,...
    time(time_flags)+dt/2,[],state(time_flags,:)');

% plot DA trace
clim = quantile(da_matrix,[0,1],'all')';
imagesc(sp_da,...
    [trial_time(1),trial_time(end)],[1,n_trials],da_matrix',clim);

% plot value trace
clim = quantile(value_matrix,[0,1],'all')';
imagesc(sp_value,...
    [trial_time(1),trial_time(end)],[1,n_trials],value_matrix',clim);

% compute & plot average DA conditioned on CS
da_mu = nanmean(da_matrix,2);
plot(sp_da_mu,trial_time,da_mu,...
    'color','k',...
    'linewidth',1);

% compute & plot average value conditioned on CS
value_mu = nanmean(value_matrix,2);
plot(sp_value_mu,trial_time,value_mu,...
    'color','k',...
    'linewidth',1);

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
    [cs1_period,fliplr(cs1_period)],...
    [-1,-1,1,1]*range(yylim)*.02+yymax,cs1_clr,...
    'edgecolor',cs1_clr,...
    'facealpha',1,...
    'linewidth',1);
patch(sp_da_mu,...
    [cs2_period,fliplr(cs2_period)],...
    [-1,-1,1,1]*range(yylim)*.02+yymax,cs2_clr,...
    'edgecolor',cs2_clr,...
    'facealpha',1,...
    'linewidth',1);
patch(sp_da_mu,...
    [us_period,fliplr(us_period)],...
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
    mean(cs1_period),yymax*1.05,'CS1',...
    'color',cs1_clr,...
    'horizontalalignment','center',...
    'verticalalignment','bottom');
text(sp_da_mu,...
    mean(cs2_period),yymax*1.05,'CS2',...
    'color',cs2_clr,...
    'horizontalalignment','center',...
    'verticalalignment','bottom');
text(sp_da_mu,...
    mean(us_period),yymax*1.05,'US',...
    'color','k',...
    'horizontalalignment','center',...
    'verticalalignment','bottom');

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

% plot average CS1-aligned baseline signal
plot(sp_baseline,baseline_period,[0,0],':k');
da_baseline_mu = nanmean(da_baseline_snippets);
da_baseline_sig = nanstd(da_baseline_snippets);
da_baseline_sem = da_baseline_sig ./ sqrt(n_trials);
errorpatch(da_baseline_time,da_baseline_mu,da_baseline_sem,[0,0,0],...
    'edgecolor','none',...
    'facealpha',.25,...
    'parent',sp_baseline);
plot(sp_baseline,...
    da_baseline_time,da_baseline_mu,...
    'color','k',...
    'linewidth',1.5);

% plot average CS1-aligned CS1 signal
plot(sp_cs1,cs1_period,[0,0],':k');
da_cs1_mu = nanmean(da_cs1_snippets);
da_cs1_sig = nanstd(da_cs1_snippets);
da_cs1_sem = da_cs1_sig ./ sqrt(n_trials);
errorpatch(da_cs1_time,da_cs1_mu,da_cs1_sem,cs1_clr,...
    'edgecolor','none',...
    'facealpha',.25,...
    'parent',sp_cs1);
plot(sp_cs1,...
    da_cs1_time,da_cs1_mu,...
    'color',cs1_clr,...
    'linewidth',1.5);

% plot average CS1-aligned CS2 signal
plot(sp_cs2,cs2_period,[0,0],':k');
da_cs2_mu = nanmean(da_cs2_snippets);
da_cs2_sig = nanstd(da_cs2_snippets);
da_cs2_sem = da_cs2_sig ./ sqrt(n_trials);
errorpatch(da_cs2_time,da_cs2_mu,da_cs2_sem,cs2_clr,...
    'edgecolor','none',...
    'facealpha',.25,...
    'parent',sp_cs2);
plot(sp_cs2,...
    da_cs2_time,da_cs2_mu,...
    'color',cs2_clr,...
    'linewidth',1.5);

% plot average CS1-aligned US signal
plot(sp_us,us_period,[0,0],':k');
da_us_mu = nanmean(da_us_snippets);
da_us_sig = nanstd(da_us_snippets);
da_us_sem = da_us_sig ./ sqrt(n_trials);
errorpatch(da_us_time,da_us_mu,da_us_sem,[0,0,0],...
    'edgecolor','none',...
    'facealpha',.25,...
    'parent',sp_us);
plot(sp_us,...
    da_us_time,da_us_mu,...
    'color','k',...
    'linewidth',1.5);

% plot DA response at CS1 and CS2
scatter(sp_csresponse,...
    trial_idcs,da_cs1_response,20,...
    'marker','o',...
    'markerfacealpha',.5,...
    'markerfacecolor',cs1_clr,...
    'markeredgecolor',cs1_clr,...
    'linewidth',1);
scatter(sp_csresponse,...
    trial_idcs,da_cs2_response,20,...
    'marker','o',...
    'markerfacealpha',.5,...
    'markerfacecolor',cs2_clr,...
    'markeredgecolor',cs2_clr,...
    'linewidth',1);
plot(sp_csresponse,xlim(sp_csresponse),[1,1]*0,':k');

% plot DA response at US
scatter(sp_usresponse,...
    trial_idcs,da_us_response,20,...
    'marker','o',...
    'markerfacealpha',.5,...
    'markerfacecolor','k',...
    'markeredgecolor','k',...
    'linewidth',1);
plot(sp_usresponse,xlim(sp_usresponse),[1,1]*0,':k');

% test 10: DA CS response over learning (overall dynamics)
normalization_term = nanmean(...
    da_cs1_response(end - normalization_window_length + 1 : end));
da_norm_cs1_response = da_cs1_response / normalization_term;
da_norm_cs2_response = da_cs2_response / normalization_term;
plot(sp_test10_backpropagation,[1,n_rewards],[1,1]*0,'-k',...
    'linewidth',axesopt.linewidth,...
    'handlevisibility','off');
plot(sp_test10_backpropagation,[1,n_rewards],[1,1]*.5,':k',...
    'handlevisibility','off');
plot(sp_test10_backpropagation,[1,n_rewards],[1,1]*1,':k',...
    'handlevisibility','off');
scatter(sp_test10_backpropagation,...
    reward_idcs,da_norm_cs1_response,20,...
    'marker','o',...
    'markerfacealpha',.5,...
    'markerfacecolor',cs1_clr,...
    'markeredgecolor',cs1_clr,...
    'linewidth',1);
scatter(sp_test10_backpropagation,...
    reward_idcs,da_norm_cs2_response,20,...
    'marker','o',...
    'markerfacealpha',.5,...
    'markerfacecolor',cs2_clr,...
    'markeredgecolor',cs2_clr,...
    'linewidth',1);
xxlim = xlim(sp_test10_initialdynamics);
yylim = ylim(sp_test10_backpropagation);
patch(sp_test10_backpropagation,...
    [xxlim,fliplr(xxlim)],...
    [-1,-1,1,1]*range(yylim)*.01+1.5,'k',...
    'edgecolor','k',...
    'facealpha',1,...
    'linewidth',1);
text(sp_test10_backpropagation,...
    mean(xxlim),1.55,'initial',...
    'color','k',...
    'horizontalalignment','center',...
    'verticalalignment','bottom');
xxlim = xlim(sp_test10_asymptoticdynamics);
yylim = ylim(sp_test10_backpropagation);
patch(sp_test10_backpropagation,...
    [xxlim,fliplr(xxlim)],...
    [-1,-1,1,1]*range(yylim)*.01+1.5,'k',...
    'edgecolor','k',...
    'facealpha',1,...
    'linewidth',1);
text(sp_test10_backpropagation,...
    mean(xxlim),1.55,'asymptotic',...
    'color','k',...
    'horizontalalignment','center',...
    'verticalalignment','bottom');

% test 10: DA CS response over learning (asymptotic dynamics)
plot(sp_test10_asymptoticdynamics,[1,n_rewards],[1,1]*0,'-k',...
    'linewidth',axesopt.linewidth,...
    'handlevisibility','off');
plot(sp_test10_asymptoticdynamics,[1,n_rewards],[1,1]*.5,':k',...
    'handlevisibility','off');
plot(sp_test10_asymptoticdynamics,[1,n_rewards],[1,1]*1,':k',...
    'handlevisibility','off');
da_asymptotic_cs2_response = nanmean(...
    da_norm_cs2_response(end-subtraction_window_length+1:end));
patch(sp_test10_asymptoticdynamics,...
    mean(xlim(sp_test10_asymptoticdynamics))+...
    range(xlim(sp_test10_asymptoticdynamics))*[-1,1,1,-1]*1/8,...
    [0,0,1,1]*da_asymptotic_cs2_response,[1,1,1]*.75,...
    'edgecolor','k',...
    'linewidth',1.5,...
    'linestyle','-',...
    'facealpha',1);
plot(sp_test10_asymptoticdynamics,...
    xlim(sp_test10_asymptoticdynamics),[0,0],'-k',...
    'linewidth',axesopt.linewidth);

% test 10: DA CS response over learning (initial dynamics)
plot(sp_test10_initialdynamics,[1,n_rewards],[0,0],':k',...
    'handlevisibility','off');
da_cs2_cs1_diff = nanmean(...
    da_norm_cs2_response(1:subtraction_window_length) - ...
    da_norm_cs1_response(1:subtraction_window_length));
patch(sp_test10_initialdynamics,...
    mean(xlim(sp_test10_initialdynamics))+...
    range(xlim(sp_test10_initialdynamics))*[-1,1,1,-1]*1/8,...
    [0,0,1,1]*da_cs2_cs1_diff,[1,1,1]*.75,...
    'edgecolor','k',...
    'linewidth',1.5,...
    'linestyle','-',...
    'facealpha',1);
plot(sp_test10_initialdynamics,...
    xlim(sp_test10_initialdynamics),[0,0],'-k',...
    'linewidth',axesopt.linewidth);

% plot CS onset
plot(sp_da_mu,[0,0]+cs1_period(1),ylim(sp_da_mu),...
    'color','k',...
    'linestyle','--',...
    'linewidth',1);
plot(sp_da_mu,[0,0]+cs2_period(1),ylim(sp_da_mu),...
    'color','k',...
    'linestyle','--',...
    'linewidth',1);
plot(sp_value_mu,[0,0]+cs1_period(1),ylim(sp_value_mu),...
    'color','k',...
    'linestyle','--',...
    'linewidth',1);
plot(sp_value_mu,[0,0]+cs2_period(1),ylim(sp_value_mu),...
    'color','k',...
    'linestyle','--',...
    'linewidth',1);

% plot CS offset
if use_cs_offset
    plot(sp_da_mu,[0,0]+cs1_period(2),ylim(sp_da_mu),...
        'color','k',...
        'linestyle','--',...
        'linewidth',1);
    plot(sp_da_mu,[0,0]+cs2_period(2),ylim(sp_da_mu),...
        'color','k',...
        'linestyle','--',...
        'linewidth',1);
    plot(sp_value_mu,[0,0]+cs1_period(2),ylim(sp_value_mu),...
        'color','k',...
        'linestyle','--',...
        'linewidth',1);
    plot(sp_value_mu,[0,0]+cs2_period(2),ylim(sp_value_mu),...
        'color','k',...
        'linestyle','--',...
        'linewidth',1);
end

% plot US
plot(sp_da_mu,[0,0]+us_period(1),ylim(sp_da_mu),...
    'color','k',...
    'linestyle','--',...
    'linewidth',1);
plot(sp_value_mu,[0,0]+us_period(1),ylim(sp_value_mu),...
    'color','k',...
    'linestyle','--',...
    'linewidth',1);

% axes linkage
arrayfun(@(ax1,ax2,ax3,ax4)linkaxes([ax1,ax2,ax3,ax4],'x'),...
    sp_da_mu,sp_da,sp_value_mu,sp_value);
linkaxes([sp_baseline,sp_cs1,sp_cs2,sp_us],'y');

% annotate model parameters
annotateModelParameters;