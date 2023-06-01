%% experiment VI: classical conditioning - "trial-less"
% description goes here

%% initialization
Jeong2022_preface;

%% used fixed random seed
rng(0);

%% key assumptions
use_clicks = 0;
use_cs_offset = 0;

%% analysis parameters
isi_cutoff = .5;
baseline_period = [-.5,0];
cs_period = [0,.5];
us_period = [0,.5];

%% experiment parameters
cs_dur = .25;
trace_dur = 3;
icsi_mu = 33;
icsi_min = .25;
icsi_max = 99;

%% simulation parameters
n_rewards = 500;

%% inter-CS intervals
icsi_pd = truncate(makedist('exponential','mu',icsi_mu),icsi_min,icsi_max);
icsi = random(icsi_pd,n_rewards,1);
icsi = dt * round(icsi / dt);
n_bins = round(max(icsi) / icsi_mu) * 10;
icsi_edges = linspace(icsi_min,icsi_max,n_bins);
icsi_counts = histcounts(icsi,icsi_edges);
icsi_counts = icsi_counts ./ nansum(icsi_counts);
icsi_pdf = pdf(icsi_pd,icsi_edges);
icsi_pdf = icsi_pdf ./ nansum(icsi_pdf);

%% simulation time
dur = sum(icsi) + icsi_max;
time = 0 : dt : dur - dt;
n_states = numel(time);
state_edges = linspace(0,dur,n_states+1);

%% CS onset times
cs_onset_times = cumsum(icsi);
cs_onset_times = dt * round(cs_onset_times / dt);
cs_onset_counts = histcounts(cs_onset_times,state_edges);

%% CS offset times
cs_offset_times = cs_onset_times + cs_dur;
cs_offset_times = dt * round(cs_offset_times / dt);
cs_offset_counts = histcounts(cs_offset_times,state_edges);

%% CS presence flags
cs_presence = sum(...
    time >= cs_onset_times & ...
    time <= cs_offset_times,1)';

%% click times
click_times = cs_offset_times + trace_dur;
click_times = dt * round(click_times / dt);
click_counts = histcounts(click_times,state_edges);
n_clicks = sum(click_counts);

%% reaction times
reaction_times = repmat(.1,n_rewards,1);
% reaction_times = linspace(1,.1,n_rewards)';
reaction_times = max(reaction_times,dt*2);
if ~use_clicks
    reaction_times = 0;
end

%% US times
us_idcs = (1 : n_rewards)';
us_times = click_times + reaction_times;
us_times = dt * round(us_times / dt);

%% US presence flags
us_presence = sum(...
    time >= us_times & ...
    time <= us_times + cs_dur,1)';

%% CS(t)-US(t-1) intervals
csusi = abs(cs_onset_times - [-inf;us_times(1:end-1)]);
csusi_edges = 0 : isi_cutoff : isi_cutoff * n_bins;
csusi_counts = histcounts(csusi,csusi_edges);

%% US(t)-US()

%% flag previous & intermediate CS/reward pairs
intermediate_flags = icsi < (us_times - cs_onset_times);
cs = categorical(intermediate_flags,[0,1],{'CS_{prev.}','CS_{interm.}'});
cs_set = categories(cs);

% format shortG
% a = [icsi,cs_onset_times,us_times,csusi,cs_intermediate_flags];
% a(1:25,:)

%% microstimuli
stimulus_trace = stimulustracefun(y0,tau,time)';
mus = linspace(1,0,n);
microstimuli = microstimulusfun(stimulus_trace,mus,sigma);

%% UNCOMMENT TO REPLACE MICROSTIMULI WITH COMPLETE SERIAL COMPOUND
% csc = zeros(n_states,n);
% pulse_duration = .1;
% pulse_length = floor(pulse_duration / dt);
% for ii = 1 : n
%     idcs = (1 : pulse_length) + (ii - 1) * pulse_length;
%     csc(idcs,ii) = 1;
% end
% microstimuli = csc;
% microstimuli = microstimuli / max(sum(microstimuli,2));

%% concatenate all stimulus times
stimulus_times = {...
    us_times,...
    cs_onset_times};
if use_clicks
    stimulus_times = [...
        stimulus_times,...
        click_times];
end
if use_cs_offset
    stimulus_times = [...
        stimulus_times,...
        cs_offset_times];
end

%% concatenate all state flags
stimulus_presence = [...
    us_presence,...
    cs_presence];

%% TD learning
[state,value,rpe,exp6_weights] = tdlambda(...
    time,[],stimulus_times,us_times,microstimuli,[],...exp3_weights(1:end-n),...
    'alpha',alpha,...
    'gamma',gamma,...
    'lambda',lambda);
% [state,value,rpe,rwdrate,exp6_weights] = difftdlambda(...
%     time,[],stimulus_times,us_times,microstimuli,[],...
%     'alpha',alpha,...
%     'gamma',gamma,...
%     'lambda',lambda);
% [state,value,rpe,rwdrate,exp6_weights] = goldmandifftdlambda(...
%     time,stimulus_presence,us_times,[],...
%     'alpha',alpha,...
%     'gamma',gamma,...
%     'lambda',lambda,...
%     'n',n);

%% compute 'DA signal'
padded_rpe = padarray(rpe,dlight_kernel.nbins/2,0);
da = conv(padded_rpe(1:end-1),dlight_kernel.pdf,'valid');

%% get reward-aligned snippets of DA signal
da_baseline_snippets = ...
    signal2eventsnippets(time,da,cs_onset_times,baseline_period,dt);
baseline_times = cs_onset_times;
baseline_times(intermediate_flags) = ...
    baseline_times([intermediate_flags(2:end-1);false]);
[da_baseline_previous_snippets,da_baseline_time] = ...
    signal2eventsnippets(time,da,baseline_times,baseline_period,dt);
[da_cs_snippets,da_cs_time] = ...
    signal2eventsnippets(time,da,cs_onset_times,cs_period,dt);
[da_us_snippets,da_us_time] = ...
    signal2eventsnippets(time,da,us_times,us_period,dt);

%% ISI-based reward selection
valid_flags = ...
    [icsi(2:end);nan] >= isi_cutoff & ...
    icsi >= isi_cutoff & ...
    csusi >= isi_cutoff;
da_baseline_snippets(~valid_flags,:) = nan;
da_baseline_previous_snippets(~valid_flags,:) = nan;
da_cs_snippets(~valid_flags,:) = nan;
da_us_snippets(~valid_flags,:) = nan;

%% compute 'DA response' metric

% preallocation
da_bslcorrectedcs_response = nan(n_rewards,1);
da_cs_response = nan(n_rewards,1);
da_us_response = nan(n_rewards,1);

% iterate through rewards
for ii = 1 : n_rewards
    da_bslcorrectedcs_response(ii) = ...
        sum(da_cs_snippets(ii,:)) - sum(da_baseline_snippets(ii,:));
    da_cs_response(ii) = ...
        sum(da_cs_snippets(ii,:)) - sum(da_baseline_previous_snippets(ii,:));
    da_us_response(ii) = ...
        sum(da_us_snippets(ii,:)) - sum(da_baseline_previous_snippets(ii,:));
end

%% asymptote detection
ft = fittype('a + b ./ (1 + c * x)');
cs_fit = fit(...
    us_idcs(valid_flags & ~intermediate_flags),...
    da_cs_response(valid_flags & ~intermediate_flags),ft,...
    'lower',[-inf,-inf,0],...
    'upper',[+inf,+inf,+inf],...
    'startpoint',[0,0,1]);
us_fit = fit(...
    us_idcs(valid_flags & ~intermediate_flags),...
    da_us_response(valid_flags & ~intermediate_flags),ft,...
    'lower',[-inf,-inf,0],...
    'upper',[+inf,+inf,+inf],...
    'startpoint',[0,0,1]);
cs_coeffs = coeffvalues(cs_fit);
us_coeffs = coeffvalues(us_fit);
cs_hat = cs_fit(us_idcs);
us_hat = us_fit(us_idcs);
cs_asymptote_idx = find(abs(cs_hat - cs_hat(end)) < .1 * range(cs_hat),1);
us_asymptote_idx = find(abs(us_hat - us_hat(end)) < .1 * range(us_hat),1);
asymptote_idx = mean([cs_asymptote_idx,us_asymptote_idx]);
asymptotic_flags = us_idcs >= asymptote_idx;

%% figure 6: experiment VI

% figure initialization
figure(figopt,...
    'name','experiment VI: test 8');

% axes initialization
n_rows = 4;
n_cols = 6;
sp_stimulus = subplot(n_rows,n_cols,(1:n_cols/2)+n_cols*0);
sp_state = subplot(n_rows,n_cols,(1:n_cols/2)+n_cols*1);
sp_rpe = subplot(n_rows,n_cols,(1:n_cols/2)+n_cols*2);
sp_value = subplot(n_rows,n_cols,(1:n_cols/2)+n_cols*3);
sp_icsi = subplot(n_rows,n_cols,n_cols*0+n_cols/2+1);
sp_csusi = subplot(n_rows,n_cols,n_cols*0+n_cols/2+2);
sp_reaction = subplot(n_rows,n_cols,n_cols*0+n_cols/2+3);
sp_cstype = subplot(n_rows,n_cols,n_cols*1+n_cols/2+1);
sp_csresponse = subplot(n_rows,n_cols,n_cols*1+n_cols/2+2);
sp_usresponse = subplot(n_rows,n_cols,n_cols*1+n_cols/2+3);
sp_baseline = subplot(n_rows,n_cols,n_cols*2+n_cols/2+1);
sp_cs = subplot(n_rows,n_cols,n_cols*2+n_cols/2+2);
sp_us = subplot(n_rows,n_cols,n_cols*2+n_cols/2+3);
sp_test8_bslcorrected = subplot(n_rows,n_cols,n_cols*3+n_cols/2+1);
sp_test8_cs = subplot(n_rows,n_cols,n_cols*3+n_cols/2+2);
sp_test8_us = subplot(n_rows,n_cols,n_cols*3+n_cols/2+3);

% concatenate axes
sps = [...
    sp_stimulus;...
    sp_state;...
    sp_rpe;...
    sp_value;...
    sp_icsi;...
    sp_csusi;...
    sp_reaction;...
    sp_cstype;...
    sp_csresponse;...
    sp_usresponse;...
    sp_baseline;...
    sp_cs;...
    sp_us;...
    sp_test8_bslcorrected;...
    sp_test8_cs;...
    sp_test8_us;...
    ];

% axes settings
arrayfun(@(ax)set(ax.XAxis,'exponent',0),sps);
set(sps,axesopt);
set(sp_stimulus,...
    'ycolor','none');
set(sp_icsi,...
    'xlim',[0,100]);
set(sp_csusi,...
    'xlim',[0,csusi_edges(end)]);
set(sp_cstype,...
    'xlim',[0,1]+[-1,1],...
    'xtick',[0,1],...
    'xticklabel',cs_set);
set(sp_baseline,...
    'xlim',baseline_period);
set(sp_cs,...
    'xlim',cs_period);
set(sp_us,...
    'xlim',us_period);
set([sp_cs,sp_us],...
    'ycolor','none');
set([sp_test8_bslcorrected,sp_test8_cs,sp_test8_us],...
    'xlim',[-1,1],...
    'ylim',[-1,2],...
    'xtick',[],...
    'xcolor','none');

% axes titles
title(sp_baseline,'Baseline period');
title(sp_cs,'CS period');
title(sp_us,'US period');
title(sp_test8_bslcorrected,'Test VIII');
title(sp_test8_cs,'Test VIII');
title(sp_test8_us,'Test VIII');

% axes labels
xlabel(sp_stimulus,'Time (s)');
xlabel(sp_state,'Time (s)');
ylabel(sp_state,'State feature #');
xlabel(sp_rpe,'Time (s)');
ylabel(sp_rpe,'RPE (a.u.)');
xlabel(sp_value,'Time (s)');
ylabel(sp_value,'Value (a.u.)');
xlabel(sp_icsi,'Inter-CS interval (s)');
ylabel(sp_icsi,'PDF');
xlabel(sp_csusi,'CS_{interm.}-US_{prev.} interval (s)');
ylabel(sp_csusi,'Count');
xlabel(sp_reaction,'Time (s)');
ylabel(sp_reaction,'Reaction time (s)');
ylabel(sp_cstype,'Count');
xlabel(sp_csresponse,'Reward #');
ylabel(sp_csresponse,'DA CS response (a.u.)');
xlabel(sp_usresponse,'Reward #');
ylabel(sp_usresponse,'DA US response (a.u.)');
xlabel(sp_baseline,'Time relative to CS onset (s)');
ylabel(sp_baseline,'DA (a.u.)');
xlabel(sp_cs,'Time relative to CS onset (s)');
ylabel(sp_cs,'DA (a.u.)');
xlabel(sp_us,'Time relative to US (s)');
ylabel(sp_us,'DA (a.u.)');
ylabel(sp_test8_bslcorrected,...
    {'Ratio of baseline-corrected','CS response (interm. / prev.)'});
ylabel(sp_test8_cs,...
    {'Ratio of CS response','(interm. / prev.)'});
ylabel(sp_test8_us,...
    {'Ratio of US response','(interm. / prev.)'});

% time selection
last_intermediate_idx = find(intermediate_flags & valid_flags,1,'last');
dur2plot = 60;
time_flags = ...
    time >= cs_onset_times(last_intermediate_idx) - dur2plot / 2 & ...
    time < cs_onset_times(last_intermediate_idx) + dur2plot / 2;
idcs = find(time_flags);
time_win = [time(idcs(1)),time(idcs(end))];

% plot stimulus trace
if use_clicks
    stem(sp_stimulus,...
        time(idcs),click_counts(idcs),...
        'color','k',...
        'marker','none');
end
% STIMOFFSET !!!!!!!!!!!!!!!!!!!!!!!!!!!! patch maybe?
stem(sp_stimulus,...
    cs_onset_times(~intermediate_flags),ones(sum(~intermediate_flags),1),...
    'color',cs_previous_clr,...
    'marker','none',...
    'linewidth',1);
stem(sp_stimulus,...
    cs_onset_times(intermediate_flags),ones(sum(intermediate_flags),1),...
    'color',cs_intermediate_clr,...
    'marker','none',...
    'linewidth',1);
stem(sp_stimulus,...
    us_times(~intermediate_flags),ones(sum(~intermediate_flags),1),...
    'color',cs_previous_clr,...
    'marker','.',...
    'markersize',20,...
    'linewidth',1);
stem(sp_stimulus,...
    us_times(intermediate_flags),ones(sum(intermediate_flags),1),...
    'color',cs_intermediate_clr,...
    'marker','.',...
    'markersize',20,...
    'linewidth',1);

% plot state features
imagesc(sp_state,time+dt/2,[],state');

% plot RPE
stem(sp_rpe,time,rpe,...
    'color','k',...
    'marker','none');

% plot DA signal
plot(sp_rpe,time,da/max(dlight_kernel.pdf),...
    'color',highlight_clr);

% plot value trace
stairs(sp_value,time,value,...
    'color','k');

% update axis limits
set([sp_stimulus,sp_state,sp_rpe,sp_value],...
    'xlim',time_win);

% legend
if use_clicks
    leg_str = ['click';cs_set;strrep(cs_set,'CS','US')];
else
    leg_str = [cs_set;strrep(cs_set,'CS','US')];
end
legend(sp_stimulus(1),leg_str,...
    'location','best',...
    'box','off');

% plot inter-CS-interval distribution
stem(sp_icsi,icsi_mu,max([icsi_counts,icsi_pdf]),...
    'color','k',...
    'marker','v',...
    'markersize',10,...
    'markerfacecolor','k',...
    'markeredgecolor','none',...
    'linewidth',2);
histogram(sp_icsi,...
    'binedges',icsi_edges,...
    'bincounts',icsi_counts .* (icsi_edges(1:end-1)>=isi_cutoff),...
    'facecolor','w',...
    'edgecolor','k',...
    'facealpha',1,...
    'linewidth',1);
histogram(sp_icsi,...
    'binedges',icsi_edges,...
    'bincounts',icsi_counts .* (icsi_edges(1:end-1)<isi_cutoff),...
    'facecolor',[1,1,1] *.75,...
    'edgecolor','k',...
    'facealpha',1,...
    'linewidth',1);
plot(sp_icsi,icsi_edges,icsi_pdf,...
    'color','k',...
    'linewidth',2);

% plot CS(intermediate)-US(previous) interval distribution
histogram(sp_csusi,...
    'binedges',csusi_edges,...
    'bincounts',csusi_counts .* (csusi_edges(1:end-1)>=isi_cutoff),...
    'facecolor','w',...
    'edgecolor','k',...
    'facealpha',1,...
    'linewidth',1);
histogram(sp_csusi,...
    'binedges',csusi_edges,...
    'bincounts',csusi_counts .* (csusi_edges(1:end-1)<isi_cutoff),...
    'facecolor',[1,1,1] *.75,...
    'edgecolor','k',...
    'facealpha',1,...
    'linewidth',1);

% plot reaction times
if use_clicks
    plot(sp_reaction,...
        us_times,reaction_times,...
        'color','k',...
        'marker','.',...
        'markersize',5,...
        'linestyle','none');
end

% plot CS distribution
patch(sp_cstype,...
    0+[-1,1,1,-1]*1/4,[0,0,1,1]*sum(~intermediate_flags),...
    cs_previous_clr,...
    'edgecolor',cs_previous_clr,...
    'linewidth',1.5,...
    'facealpha',2/3);
patch(sp_cstype,...
    1+[-1,1,1,-1]*1/4,[0,0,1,1]*sum(intermediate_flags),...
    cs_intermediate_clr,...
    'edgecolor',cs_intermediate_clr,...
    'linewidth',1.5,...
    'facealpha',2/3);

% plot CS response
scatter(sp_csresponse,...
    us_idcs(~intermediate_flags),...
    da_cs_response(~intermediate_flags),20,...
    'marker','o',...
    'markerfacealpha',.5,...
    'markerfacecolor',cs_previous_clr,...
    'markeredgecolor',cs_previous_clr,...
    'linewidth',1);
scatter(sp_csresponse,...
    us_idcs(intermediate_flags),...
    da_cs_response(intermediate_flags),20,...
    'marker','o',...
    'markerfacealpha',.5,...
    'markerfacecolor',cs_intermediate_clr,...
    'markeredgecolor',cs_intermediate_clr,...
    'linewidth',1);
plot(sp_csresponse,us_idcs,cs_hat,...
    'color',cs_previous_clr,...
    'linestyle','-',...
    'linewidth',3);
plot(sp_csresponse,us_idcs,cs_hat,...
    'color','w',...
    'linestyle','-',...
    'linewidth',1.5);
plot(sp_csresponse,asymptote_idx*[1,1],ylim(sp_csresponse),'--k');
plot(sp_csresponse,xlim(sp_csresponse),[1,1]*0,':k');

% plot US response
scatter(sp_usresponse,...
    us_idcs(~intermediate_flags),...
    da_us_response(~intermediate_flags),20,...
    'marker','o',...
    'markerfacealpha',.5,...
    'markerfacecolor',cs_previous_clr,...
    'markeredgecolor',cs_previous_clr,...
    'linewidth',1);
scatter(sp_usresponse,...
    us_idcs(intermediate_flags),...
    da_us_response(intermediate_flags),20,...
    'marker','o',...
    'markerfacealpha',.5,...
    'markerfacecolor',cs_intermediate_clr,...
    'markeredgecolor',cs_intermediate_clr,...
    'linewidth',1);
plot(sp_usresponse,us_idcs,us_hat,...
    'color',cs_previous_clr,...
    'linestyle','-',...
    'linewidth',3);
plot(sp_usresponse,us_idcs,us_hat,...
    'color','w',...
    'linestyle','-',...
    'linewidth',1.5);
plot(sp_usresponse,asymptote_idx*[1,1],ylim(sp_usresponse),'--k');
plot(sp_usresponse,xlim(sp_usresponse),[1,1]*0,':k');

% plot average CS-aligned baseline signal
plot(sp_baseline,baseline_period,[0,0],':k');
da_baseline_mu = nanmean(da_baseline_previous_snippets(~intermediate_flags & asymptotic_flags,:));
da_baseline_sig = nanstd(da_baseline_previous_snippets(~intermediate_flags & asymptotic_flags,:));
da_baseline_sem = da_baseline_sig ./ sqrt(sum(~intermediate_flags & asymptotic_flags));
errorpatch(da_baseline_time,da_baseline_mu,da_baseline_sem,cs_previous_clr,...
    'edgecolor','none',...
    'facealpha',.25,...
    'parent',sp_baseline);
plot(sp_baseline,...
    da_baseline_time,da_baseline_mu,...
    'color',cs_previous_clr,...
    'linestyle','-',...
    'linewidth',1.5);
da_baseline_mu = nanmean(da_baseline_previous_snippets(intermediate_flags & asymptotic_flags,:));
da_baseline_sig = nanstd(da_baseline_previous_snippets(intermediate_flags & asymptotic_flags,:));
da_baseline_sem = da_baseline_sig ./ sqrt(sum(intermediate_flags & asymptotic_flags));
errorpatch(da_baseline_time,da_baseline_mu,da_baseline_sem,cs_intermediate_clr,...
    'edgecolor','none',...
    'facealpha',.25,...
    'parent',sp_baseline);
plot(sp_baseline,...
    da_baseline_time,da_baseline_mu,...
    'color',cs_intermediate_clr,...
    'linestyle','-',...
    'linewidth',1.5);
da_baseline_mu = nanmean(da_baseline_snippets(intermediate_flags & asymptotic_flags,:));
da_baseline_sig = nanstd(da_baseline_snippets(intermediate_flags & asymptotic_flags,:));
da_baseline_sem = da_baseline_sig ./ sqrt(sum(intermediate_flags & asymptotic_flags));
errorpatch(da_baseline_time,da_baseline_mu,da_baseline_sem,cs_intermediate_clr,...
    'edgecolor','none',...
    'facealpha',.25,...
    'parent',sp_baseline);
plot(sp_baseline,...
    da_baseline_time,da_baseline_mu,...
    'color',cs_intermediate_clr,...
    'linestyle','--',...
    'linewidth',1.5);

% plot average CS-aligned signal
plot(sp_cs,cs_period,[0,0],':k');
da_cs_mu = nanmean(da_cs_snippets(~intermediate_flags & asymptotic_flags,:));
da_cs_sig = nanstd(da_cs_snippets(~intermediate_flags & asymptotic_flags,:));
da_cs_sem = da_cs_sig ./ sqrt(sum(~intermediate_flags & asymptotic_flags));
errorpatch(da_cs_time,da_cs_mu,da_cs_sem,cs_previous_clr,...
    'edgecolor','none',...
    'facealpha',.25,...
    'parent',sp_cs);
plot(sp_cs,...
    da_cs_time,da_cs_mu,...
    'color',cs_previous_clr,...
    'linewidth',1.5);
da_cs_mu = nanmean(da_cs_snippets(intermediate_flags & asymptotic_flags,:));
da_cs_sig = nanstd(da_cs_snippets(intermediate_flags & asymptotic_flags,:));
da_cs_sem = da_cs_sig ./ sqrt(sum(intermediate_flags & asymptotic_flags));
errorpatch(da_cs_time,da_cs_mu,da_cs_sem,cs_intermediate_clr,...
    'edgecolor','none',...
    'facealpha',.25,...
    'parent',sp_cs);
plot(sp_cs,...
    da_cs_time,da_cs_mu,...
    'color',cs_intermediate_clr,...
    'linewidth',1.5);

% plot average US-aligned signal
plot(sp_us,us_period,[0,0],':k');
da_us_mu = nanmean(da_us_snippets(~intermediate_flags & asymptotic_flags,:));
da_us_sig = nanstd(da_us_snippets(~intermediate_flags & asymptotic_flags,:));
da_us_sem = da_us_sig ./ sqrt(sum(~intermediate_flags & asymptotic_flags));
errorpatch(da_us_time,da_us_mu,da_us_sem,cs_previous_clr,...
    'edgecolor','none',...
    'facealpha',.25,...
    'parent',sp_us);
plot(sp_us,...
    da_us_time,da_us_mu,...
    'color',cs_previous_clr,...
    'linewidth',1.5);
da_us_mu = nanmean(da_us_snippets(intermediate_flags & asymptotic_flags,:));
da_us_sig = nanstd(da_us_snippets(intermediate_flags & asymptotic_flags,:));
da_us_sem = da_us_sig ./ sqrt(sum(intermediate_flags & asymptotic_flags));
errorpatch(da_us_time,da_us_mu,da_us_sem,cs_intermediate_clr,...
    'edgecolor','none',...
    'facealpha',.25,...
    'parent',sp_us);
plot(sp_us,...
    da_us_time,da_us_mu,...
    'color',cs_intermediate_clr,...
    'linewidth',1.5);

% test 8: Ratio of baseline-corrected CS responses (intermediate / previous)
bslcorrcs_response_ratio = ...
    nanmean(da_bslcorrectedcs_response(intermediate_flags & asymptotic_flags)) / ...
    nanmean(da_bslcorrectedcs_response(~intermediate_flags & asymptotic_flags));
plot(sp_test8_bslcorrected,[-1,1],[-1,-1],':k');
plot(sp_test8_bslcorrected,[-1,1],[1,1],':k');
patch(sp_test8_bslcorrected,...
    0+[-1,1,1,-1]*1/4,[0,0,1,1]*bslcorrcs_response_ratio,[1,1,1]*.75,...
    'edgecolor','k',...
    'linewidth',1.5,...
    'linestyle','--',...
    'facealpha',1);
plot(sp_test8_bslcorrected,[-1,1],[0,0],'-k',...
    'linewidth',axesopt.linewidth);

% test 8: Ratio of CS responses (intermediate / previous)
cs_response_ratio = ...
    nanmean(da_cs_response(intermediate_flags & asymptotic_flags)) / ...
    nanmean(da_cs_response(~intermediate_flags & asymptotic_flags));
plot(sp_test8_cs,[-1,1],[-1,-1],':k');
plot(sp_test8_cs,[-1,1],[1,1],':k');
patch(sp_test8_cs,...
    0+[-1,1,1,-1]*1/4,[0,0,1,1]*cs_response_ratio,[1,1,1]*.75,...
    'edgecolor','k',...
    'linewidth',1.5,...
    'linestyle','-',...
    'facealpha',1);
plot(sp_test8_cs,[-1,1],[0,0],'-k',...
    'linewidth',axesopt.linewidth);

% test 8: Ratio of US responses (intermediate / previous)
us_response_ratio = ...
    nanmean(da_us_response(intermediate_flags & asymptotic_flags)) / ...
    nanmean(da_us_response(~intermediate_flags & asymptotic_flags));
plot(sp_test8_us,[-1,1],[-1,-1],':k');
plot(sp_test8_us,[-1,1],[1,1],':k');
patch(sp_test8_us,...
    0+[-1,1,1,-1]*1/4,[0,0,1,1]*us_response_ratio,[1,1,1]*.75,...
    'edgecolor','k',...
    'linewidth',1.5,...
    'linestyle','-',...
    'facealpha',1);
plot(sp_test8_us,[-1,1],[0,0],'-k',...
    'linewidth',axesopt.linewidth);

% axes linkage
arrayfun(@(ax1,ax2,ax3,ax4)linkaxes([ax1,ax2,ax3,ax4],'x'),...
    sp_stimulus,sp_state,sp_rpe,sp_value);
linkaxes(sp_rpe,'y');
linkaxes(sp_value,'y');
linkaxes([sp_baseline,sp_cs,sp_us],'y');
linkaxes([sp_test8_bslcorrected,sp_test8_cs,sp_test8_us],'y');

% annotate model parameters
annotateModelParameters;