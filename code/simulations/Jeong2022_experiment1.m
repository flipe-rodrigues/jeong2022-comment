%% experiment I: unpredicted rewards
% description goes here

%% initialization
Jeong2022_preface;

%% used fixed random seed
rng(0);

%% key assumptions
use_clicks = 0;
use_licks = 0;

%% experiment parameters
iri_mu = 12;

%% analysis parameters
baseline_period = [-2,-.5];
reward_period = [-.5,1];
iri_cutoff = 3;

%% simulation parameters
% load('exp1data');
% load('randomrewards');
for mm = 1 % : 8
%     reaction_times = max(0,reaction_times_cell{mm} - .25); % !!!!!!!!!!!!!
%     lick_times = lick_times_cell{mm};
%     n_rewards = numel(reaction_times);
    n_rewards = 10000;
    
    %% training stage settings
    n_stages = 3;
    stage_dur = 60;
    early_clr = [0,0,0];
    late_clr = [1,1,1] * .85;
    stage_clrs = colorlerp([early_clr; late_clr],n_stages);
    
    %% inter-reward-intervals
    iri_pd = makedist('exponential','mu',iri_mu);
    iri = random(iri_pd,n_rewards,1);
    
    %% time
    dur = sum(iri) + max(iri);
    time = 0 : dt : dur - dt;
    n_states = numel(time);
    state_edges = linspace(0,dur,n_states+1);
    
    %% click times
    click_times = cumsum(iri);
    click_times = dt * round(click_times / dt);
    click_counts = histcounts(click_times,state_edges);
    
    %% reaction times
    % reaction_times = repmat(.5,n_rewards,1);
    % reaction_times = linspace(1,max(.1,dt*2),n_rewards)';
    % reaction_times = normalize01(click_times .^ -dt) + .1;
    % reaction_times = normalize01(1 ./ (1 + .005 .* click_times)) + .1;
    % reaction_times = exprnd(.5,n_clicks,1);
    % reaction_times = exprnd(linspace(1.5,1/3,n_clicks)',n_clicks,1);
    if ~use_clicks
        reaction_times = 0;
    end
    
    %% reward times
    reward_times = click_times + reaction_times;
    reward_times = dt * round(reward_times / dt);
    
    %% reward presence flags
    reward_presence = sum(...
        time >= reward_times & ...
        time <= reward_times + .25,1)';
    
    %% inter-reward-intervals
    iri_n_bins = round(max(iri) / iri_mu) * 10;
    iri_edges = linspace(0,max(iri),iri_n_bins);
    iri_counts = histcounts(iri,iri_edges);
    iri_pmf = iri_counts ./ nansum(iri_counts);
    iri_pdf = pdf(iri_pd,iri_edges);
    iri_pdf = iri_pdf ./ nansum(iri_pdf);
    
    %% IRI hazard rate
    iri_cdf = cumsum(iri_pdf);
    iri_survival = 1 - [0, iri_cdf(1:end-1)];
    iri_hzd = round(iri_pdf ./ iri_survival,4);
    iri_cdf_empirical = cumsum(iri_pmf);
    iri_survival_empirical = 1 - [0, iri_cdf_empirical(1:end-1)];
    iri_hzd_empirical = iri_pmf ./ iri_survival_empirical;
    
    %% IRI subjective hazard rate
    webber_fraction = .15;
    sig0 = .05;
    
    % define gaussian kernel to introduce scalar timing
    kernel.weber.win = iri_edges;
    kernel.weber.mus = kernel.weber.win';
    kernel.weber.sigs = kernel.weber.mus * webber_fraction;
    kernel.weber.pdfs = normpdf(kernel.weber.win,kernel.weber.mus,kernel.weber.sigs);
    I = eye(iri_n_bins);
    for jj = 1 : iri_n_bins
        if all(isnan(kernel.weber.pdfs(jj,:)))
            kernel.weber.pdfs(jj,:) = I(jj,:);
        end
    end
    kernel.weber.pdfs = kernel.weber.pdfs ./ nansum(kernel.weber.pdfs,2);
    
    % smear iri distro with scalar kernel
    iri_pdf_subjective = iri_pdf * kernel.weber.pdfs';
    iri_pdf_subjective = iri_pdf_subjective / nansum(iri_pdf_subjective);
    iri_cdf_subjective = cumsum(iri_pdf_subjective);
    iri_survival_subjective = 1 - [0, iri_cdf_subjective(1:end-1)];
    iri_hzd_subjective = round(iri_pdf_subjective ./ iri_survival_subjective,4);
    
    %% microstimuli
    stimulus_trace = stimulustracefun(y0,tau,time)';
    mus = linspace(1,0,n);
    microstimuli = microstimulusfun(stimulus_trace,mus,sigma);
    
    %% UNCOMMENT TO REPLACE MICROSTIMULI WITH COMPLETE SERIAL COMPOUND
    csc = zeros(n_states,n);
    pulse_duration = .2;
    pulse_length = floor(pulse_duration / dt);
    for ii = 1 : n
        idcs = (1 : pulse_length) + (ii - 1) * pulse_length;
        csc(idcs,ii) = 1;
    end
    microstimuli = csc;
    microstimuli = microstimuli / max(sum(microstimuli,2));
    
    %% elibility traces
    eligibility = zeros(n_states,n);
    for ss = 2 : n_states
        eligibility(ss,:) = ...
            gamma * lambda * eligibility(ss-1,:) + microstimuli(ss-1,:);
    end
    
    %% concatenate all stimulus times
    stimulus_times = {...
        reward_times};
    if use_clicks
        stimulus_times = [...
            stimulus_times,...
            click_times];
    end
    if use_licks
        stimulus_times = [...
            stimulus_times,...
            lick_times];
    end
    
    %% concatenate all state flags
    stimulus_presence = [...
        reward_presence];
    
    %% TD learning
    [state,value,rpe,exp1_weights] = tdlambda(...
        time,[],stimulus_times,reward_times,microstimuli,[],...
        'alpha',alpha,...
        'gamma',gamma,...
        'lambda',lambda,...
        'tau',tau);
    % [state,value,rpe,rwdrate,exp1_weights] = difftdlambda(...
    %     time,[],stimulus_times,reward_times,microstimuli,[],...
    %     'alpha',alpha,...
    %     'gamma',gamma,...
    %     'lambda',lambda,...
    %     'tau',tau);
    % [state,value,rpe,rwdrate,exp1_weights] = goldmandifftdlambda(...
    %     time,stimulus_presence,reward_times,[],...
    %     'alpha',alpha,...
    %     'gamma',gamma,...
    %     'lambda',lambda,...
    %     'n',n);
    
    %% compute 'DA signal'
    padded_rpe = padarray(rpe,dlight_kernel.nbins/2,0);
    if use_dlight_kernel
        da = conv(padded_rpe(1:end-1),dlight_kernel.pdf,'valid');
    else
        da = rpe;
    end
    da = da + psi * max(dlight_kernel.pdf);
    
    %% get reward-aligned snippets of DA & value signals
    [da_baseline_snippets,da_baseline_time] = ...
        signal2eventsnippets(time,da,reward_times,baseline_period,dt);
    [da_reward_snippets,da_reward_time] = ...
        signal2eventsnippets(time,da,reward_times,reward_period,dt);
    [value_snippets,value_time] = ...
        signal2eventsnippets(time,value,reward_times,[-10,40],dt);
    
    %% IRI-based reward selection
    iri_flags = ...
        [iri(2:end);nan] >= iri_cutoff * 1 & ...
        iri >= iri_cutoff;
    da_baseline_snippets(~iri_flags,:) = nan;
    da_reward_snippets(~iri_flags,:) = nan;
    value_snippets(~iri_flags,:) = nan;
    
    %% compute 'DA response' metric
    
    % preallocation
    da_response = nan(n_rewards,1);
    
    % iterate through rewards
    for ii = 1 : n_rewards
        da_response(ii) = ...
            sum(da_reward_snippets(ii,:)) - sum(da_baseline_snippets(ii,:));
    end
    
    %% compute training stage indices
    stage_dur = min(stage_dur,dur/n_stages);
    n_states_per_stage = floor(n_states * min(stage_dur/dur,1/n_stages));
    n_stage_divisors = floor(n_states / n_states_per_stage);
    divisor_state_idcs = (0 : n_stage_divisors - 1) * n_states_per_stage;
    stage_divisor_idcs = floor(linspace(1,n_stage_divisors,n_stages));
    stage_state_idcs = (1 : n_states_per_stage)' + ...
        divisor_state_idcs(stage_divisor_idcs);
    
    %% figure 1: experiment I
    
    % figure initialization
    figure(figopt,...
        'name','experiment I: tests 1 & 2');
    
    % axes initialization
    n_rows = 4;
    n_cols = n_stages + 3;
    sp_stimulus = gobjects(1,n_stages);
    sp_state = gobjects(1,n_stages);
    sp_rpe = gobjects(1,n_stages);
    sp_value = gobjects(1,n_stages);
    for ii = 1 : n_stages
        sp_stimulus(ii) = subplot(n_rows,n_cols,ii+n_cols*0);
        sp_state(ii) = subplot(n_rows,n_cols,ii+n_cols*1);
        sp_rpe(ii) = subplot(n_rows,n_cols,ii+n_cols*2);
        sp_value(ii) = subplot(n_rows,n_cols,ii+n_cols*3);
    end
    sp_iri = subplot(n_rows,n_cols,n_cols-2+n_cols*0);
    sp_hazard = subplot(n_rows,n_cols,n_cols-1+n_cols*0);
    sp_reaction = subplot(n_rows,n_cols,n_cols+n_cols*0);
    sp_stimulustrace = subplot(n_rows,n_cols,n_cols-2+n_cols*1);
    sp_microstimulus = subplot(n_rows,n_cols,n_cols-1+n_cols*1);
    sp_eligibility = subplot(n_rows,n_cols,n_cols+n_cols*1);
    sp_dlightkernel = subplot(n_rows,n_cols,n_cols-2+n_cols*2);
    sp_baseline = subplot(n_rows,n_cols,n_cols-1+n_cols*2);
    sp_reward = subplot(n_rows,n_cols,n_cols+n_cols*2);
    sp_value_mu = subplot(n_rows,n_cols,n_cols-2+n_cols*3);
    sp_test1 = subplot(n_rows,n_cols,n_cols-1+n_cols*3);
    sp_test2 = subplot(n_rows,n_cols,n_cols+n_cols*3);
    
    % concatenate axes
    sp_stage = [...
        sp_stimulus;...
        sp_state;...
        sp_rpe;...
        sp_value...
        ];
    sps = [...
        sp_stage(:);...
        sp_iri;...
        sp_hazard;...
        sp_reaction;...
        sp_stimulustrace;...
        sp_microstimulus;...
        sp_eligibility;...
        sp_dlightkernel;...
        sp_baseline;...
        sp_reward;...
        sp_value_mu;...
        sp_test1;...
        sp_test2;...
        ];
    
    % axes settings
    arrayfun(@(ax)set(ax.XAxis,'exponent',0),sps);
    set(sps,axesopt);
    set(sp_stage(:,2:end),...
        'ycolor','none');
    set(sp_stimulus,...
        'ylim',[0,1.5],...
        'ycolor','none');
    set([sp_iri,sp_hazard,sp_stimulustrace,sp_microstimulus,sp_eligibility],...
        'xlim',[0,40]);
    set(sp_value_mu,...
        'xlim',[value_time(1),value_time(end)]);
    set([sp_stimulustrace,sp_hazard],...
        'ylim',[0,1]);
    set(sp_reward,...
        'ycolor','none');
    
    % axes titles
    title(sp_stimulus(1),'Early in training');
    title(sp_stimulus(end),'Late in training');
    title(sp_dlightkernel,'dLight kernel');
    title(sp_baseline,'Baseline period');
    title(sp_reward,'Reward period');
    title(sp_test1,'Test I');
    title(sp_test2,'Test II');
    
    % axes labels
    arrayfun(@(ax)xlabel(ax,'Time (s)'),sp_stimulus);
    arrayfun(@(ax)ylabel(ax,'Stimulus trace (a.u.)'),sp_stimulus);
    arrayfun(@(ax)xlabel(ax,'Time (s)'),sp_state);
    arrayfun(@(ax)ylabel(ax,'State feature #'),sp_state);
    arrayfun(@(ax)xlabel(ax,'Time (s)'),sp_rpe);
    arrayfun(@(ax)ylabel(ax,'RPE (a.u.)'),sp_rpe);
    arrayfun(@(ax)xlabel(ax,'Time (s)'),sp_value);
    arrayfun(@(ax)ylabel(ax,'Value (a.u.)'),sp_value);
    xlabel(sp_iri,'IRI (s)');
    ylabel(sp_iri,'PDF');
    xlabel(sp_hazard,'IRI (s)');
    ylabel(sp_hazard,'Hazard');
    xlabel(sp_reaction,'Time (s)');
    ylabel(sp_reaction,'Reaction time (s)');
    xlabel(sp_microstimulus,'Time (s)');
    ylabel(sp_microstimulus,'Temporal basis (a.u.)');
    xlabel(sp_stimulustrace,'Time (s)');
    ylabel(sp_stimulustrace,'Stimulus trace (a.u.)');
    xlabel(sp_eligibility,'Time (s)');
    ylabel(sp_eligibility,'Eligibility trace (a.u.)');
    xlabel(sp_dlightkernel,'Time (s)');
    ylabel(sp_dlightkernel,'PDF (a.u.)');
    xlabel(sp_baseline,'Time relative to reward (s)');
    ylabel(sp_baseline,'DA (a.u.)');
    xlabel(sp_reward,'Time relative to reward (s)');
    ylabel(sp_reward,'DA (a.u.)');
    xlabel(sp_value_mu,'Time relative to reward (s)');
    ylabel(sp_value_mu,'Value (a.u.)');
    xlabel(sp_test1,'Reward #');
    ylabel(sp_test1,'DA response (a.u.)');
    xlabel(sp_test2,'Previous IRI (s)');
    ylabel(sp_test2,'DA response (a.u.)');
    
    % iterate through training stages
    for ii = 1 : n_stages
        idcs = stage_state_idcs(:,ii);
        time_win = [time(idcs(1)),time(idcs(end))];
        
        % plot stimulus trace
        if use_clicks
            stem(sp_stimulus(ii),...
                click_times,ones(n_rewards,1),...
                'color',[1,1,1]*.75,...
                'marker','none',...
                'linewidth',1);
        end
        stem(sp_stimulus(ii),...
            reward_times,ones(n_rewards,1),...
            'color','k',...
            'marker','.',...
            'markersize',15,...
            'linewidth',1);
        
        % plot state features
        imagesc(sp_state(ii),time+dt/2,[],state');
        
        % plot RPE
        stem(sp_rpe(ii),time,rpe,...
            'color','k',...
            'marker','none',...
            'linewidth',1);
        
        % plot DA signal
        plot(sp_rpe(ii),time,da,...
            'color',highlight_clr);
        
        % plot value trace
        stairs(sp_value(ii),time,value,...
            'color','k');
        
        % update axis limits
        set(sp_stage(:,ii),...
            'xlim',time_win);
    end
    
    % legends
    if use_clicks
        leg_str = {'click','reward'};
    else
        leg_str = {'reward'};
    end
    legend(sp_stimulus(1),leg_str,...
        'location','northwest',...
        'box','off',...
        'autoupdate','off');
    legend(sp_rpe(1),{'RPE','DA'},...
        'location','northwest',...
        'box','off',...
        'autoupdate','off');
    
    % plot response windows used to compute DA responses
    n_stage_rewards = sum(reward_times <= time(stage_state_idcs(end,1)));
    [~,eg_reward_idx] = max(...
        iri(2:n_stage_rewards+2) + [0;iri(3:n_stage_rewards+2)]);
    stem(sp_stimulus(1),...
        reward_times(eg_reward_idx),1,...
        'color',highlight_clr,...
        'marker','.',...
        'markersize',15,...
        'linewidth',1);
    yylim = ylim(sp_stimulus(1));
    yymax = 1.15;
    patch(sp_stimulus(1),...
        [baseline_period,fliplr(baseline_period)]+reward_times(eg_reward_idx),...
        [-1,-1,1,1]*range(yylim)*.02+yymax,'w',...
        'edgecolor',highlight_clr,...
        'facealpha',1,...
        'linewidth',1);
    patch(sp_stimulus(1),...
        [reward_period,fliplr(reward_period)]+reward_times(eg_reward_idx),...
        [-1,-1,1,1]*range(yylim)*.02+yymax,highlight_clr,...
        'edgecolor',highlight_clr,...
        'facealpha',1,...
        'linewidth',1);
    
    % plot IRI distribution
    stem(sp_iri,iri_mu,max([iri_pmf,iri_pdf]),...
        'color','k',...
        'marker','v',...
        'markersize',10,...
        'markerfacecolor','k',...
        'markeredgecolor','none',...
        'linewidth',2);
    histogram(sp_iri,...
        'binedges',iri_edges,...
        'bincounts',iri_pmf .* (iri_edges(1:end-1)>=iri_cutoff),...
        'facecolor','w',...
        'edgecolor','k',...
        'facealpha',1,...
        'linewidth',1);
    histogram(sp_iri,...
        'binedges',iri_edges,...
        'bincounts',iri_pmf .* (iri_edges(1:end-1)<iri_cutoff),...
        'facecolor',[1,1,1] *.75,...
        'edgecolor','k',...
        'facealpha',1,...
        'linewidth',1);
    plot(sp_iri,iri_edges,iri_pdf,...
        'color','k',...
        'linewidth',2);
    
    % plot IRI hazard rate
    stairs(sp_hazard,iri_edges(1:end-1),iri_hzd_empirical,...
        'color','k',...
        'linestyle','-',...
        'linewidth',1);
    plot(sp_hazard,iri_edges,iri_hzd,...
        'color','k',...
        'linestyle','-',...
        'linewidth',2);
    
    % plot reaction times
    plot(sp_reaction,...
        reward_times,reaction_times,...
        'color','k',...
        'marker','.',...
        'markersize',5,...
        'linestyle','none');
    
    % plot stimulus trace
    plot(sp_stimulustrace,...
        time(time < max(xlim(sp_microstimulus))),...
        stimulus_trace(time < max(xlim(sp_microstimulus))),...
        'color','k',...
        'linewidth',2);
    text(sp_stimulustrace,...
        .5,.75,sprintf('y(t) = \\tau^t'),...
        'fontsize',axesopt.fontsize+2,...
        'units','normalized',...
        'horizontalalignment','center');
    
    % plot microstimuli
    plot(sp_microstimulus,...
        time(time < max(xlim(sp_microstimulus))),...
        microstimuli(time < max(xlim(sp_microstimulus)),:),...
        'color','k');
    
    % plot eligibility traces
    plot(sp_eligibility,...
        time(time < max(xlim(sp_eligibility))),...
        eligibility(time < max(xlim(sp_eligibility)),:),...
        'color','k');
    
    % highlight a microstimulus
    idx = floor(n * 1 / 3);
    plot(sp_microstimulus,...
        time(time < max(xlim(sp_microstimulus))),...
        microstimuli(time < max(xlim(sp_microstimulus)),idx),...
        'color','k',...
        'linewidth',2);
    plot(sp_eligibility,...
        time(time < max(xlim(sp_eligibility))),...
        eligibility(time < max(xlim(sp_eligibility)),idx),...
        'color','k',...
        'linewidth',2);
    
    % plot dlight smoothing kernel
    plot(sp_dlightkernel,...
        dlight_kernel.x,dlight_kernel.pdf,...
        'color',highlight_clr,...
        'linewidth',1.5);
    
    % plot average reward-aligned DA & value snippets
    for ii = 1 : n_stages
        idcs = (1 : floor(n_rewards/n_stages)) + ...
            (ii -1) * floor(n_rewards/n_stages);
        
        % average reward-aligned reward signal
        da_reward_mu = nanmean(da_reward_snippets(idcs,:));
        plot(sp_reward,da_reward_time,da_reward_mu,...
            'color',stage_clrs(ii,:),...
            'linewidth',1.5);
        
        % average reward-aligned baseline signal
        da_baseline_mu = nanmean(da_baseline_snippets(idcs,:));
        plot(sp_baseline,da_baseline_time,da_baseline_mu,...
            'color',stage_clrs(ii,:),...
            'linewidth',1.5);
        
        % plot average value aligned to reward
        errorpatch(...
            value_time,...
            nanmean(value_snippets(idcs,:)),...
            nanstd(value_snippets(idcs,:))./sqrt(numel(idcs)),...
            stage_clrs(ii,:),...
            'facealpha',.25,...
            'parent',sp_value_mu);
        plot(sp_value_mu,...
            value_time,nanmean(value_snippets(idcs,:)),...
            'linewidth',1.5,...
            'color',stage_clrs(ii,:));
    end
    
    % legend
    legend_labels = repmat({''},n_stages,1);
    legend_labels{1} = 'Early';
    legend_labels{end} = 'Late';
    legend(sp_baseline,legend_labels,...
        'location','northwest',...
        'box','off');
    
    % test 1: DA responses as a function of reward number
    nan_flags = isnan(da_response);
    reward_idcs = (1 : n_rewards)';
    xx = reward_idcs;
    [~,sorted_idcs] = sort(iri);
    [rho,pval] = corr(xx(~nan_flags),da_response(~nan_flags));
    mdl = fitlm(xx,da_response);
    scatter(sp_test1,xx(sorted_idcs),da_response(sorted_idcs),20,...
        colorlerp([iri_short_clr; iri_long_clr],n_rewards),...
        'marker','o',...
        'markerfacealpha',.5,...
        'markerfacecolor','flat',...
        'markeredgecolor','flat',...
        'linewidth',1);
    text(sp_test1,.05,.05,'Previous IRI:',...
        'horizontalalignment','left',...
        'verticalalignment','bottom',...
        'units','normalized',...
        'color','k');
    text(sp_test1,.5,.05,'short',...
        'horizontalalignment','left',...
        'verticalalignment','bottom',...
        'units','normalized',...
        'color',iri_short_clr);
    text(sp_test1,.7,.05,'long',...
        'horizontalalignment','left',...
        'verticalalignment','bottom',...
        'units','normalized',...
        'color',iri_long_clr);
    plot(sp_test1,xx,mdl.predict(xx),...
        'color',highlight_clr,...
        'linestyle',repmat('-',1,1+(mdl.Coefficients.pValue(end)>.05)),...
        'linewidth',1.5);
    plot(sp_test1,xlim(sp_test1),[1,1]*0,':k');
    text(sp_test1,.05,.95,sprintf('r = %.2f',rho),...
        'horizontalalignment','left',...
        'verticalalignment','bottom',...
        'units','normalized',...
        'color','k');
    text(sp_test1,.05,.85,sprintf('p = %.2e',pval),...
        'horizontalalignment','left',...
        'verticalalignment','bottom',...
        'units','normalized',...
        'color','k');
    
    % test 2: DA responses as a function of previous IRI
    nan_flags = isnan(da_response);
    [rho,pval] = corr(iri(~nan_flags),da_response(~nan_flags));
    mdl = fitlm(iri,da_response);
    scatter(sp_test2,iri,da_response,20,...
        colorlerp([early_clr; late_clr],n_rewards),...
        'marker','o',...
        'markerfacealpha',.5,...
        'markerfacecolor','flat',...
        'markeredgecolor','flat',...
        'linewidth',1);
    plot(sp_test2,mdl.Variables.x1,mdl.predict(mdl.Variables.x1),...
        'color',highlight_clr,...
        'linestyle',repmat('-',1,1+(mdl.Coefficients.pValue(end)>.05)),...
        'linewidth',1.5);
    plot(sp_test2,xlim(sp_test2),[1,1]*0,':k');
    text(sp_test2,.05,.95,sprintf('r = %.2f',rho),...
        'horizontalalignment','left',...
        'verticalalignment','bottom',...
        'units','normalized',...
        'color','k');
    text(sp_test2,.05,.85,sprintf('p = %.2e',pval),...
        'horizontalalignment','left',...
        'verticalalignment','bottom',...
        'units','normalized',...
        'color','k');
    
    % axes linkage
    arrayfun(@(ax1,ax2,ax3,ax4)linkaxes([ax1,ax2,ax3,ax4],'x'),...
        sp_stimulus,sp_state,sp_rpe,sp_value);
    linkaxes([sp_microstimulus,sp_eligibility],'x');
    linkaxes(sp_rpe,'y');
    linkaxes([sp_value,sp_value_mu],'y');
    linkaxes([sp_baseline,sp_reward],'y');
    
    % annotate model parameters
    annotateModelParameters;
end
return;

%% dynamic programming approach
s = sort([1:iri_n_bins,1:iri_n_bins]);
r = repmat([0,1],1,iri_n_bins);
sp = s + 1;
sp(r == 1) = iri_n_bins;
sp(end) = 1;
p = 1 - sort([iri_hzd,iri_hzd]);
p(r == 1) = iri_hzd;
p(s == iri_n_bins - 1 & sp == iri_n_bins) = 1;
r(end) = 0;
mdp_dynamics = table(sp',r',s',p',...
    'variablenames',{'s''','r','s','p(s'',r | s)'});
mdp_dynamics = mdp_dynamics(sp <= iri_n_bins & r == (sp == iri_n_bins),:);
head(mdp_dynamics)
tail(mdp_dynamics)
whos mdp_dynamics

%% policy evaluation
figure(figopt,...
    'windowstyle','normal');
axes(axesopt,...
    'colormap',winter(2^8));
xlabel('Time (s)');
ylabel('Value (a.u.)');

% preallocation
value_function = zeros(1,iri_n_bins);

iter = 1;
theta = 1e-6;
delta = inf;
while delta > theta
    delta = 0;
    
    % iterate through states
    for ss = 1 : iri_n_bins
        temp = value_function(ss);
        Vs = 0;
        
        % iterate through subsequent states
        for sp = 1 : iri_n_bins
            
            % iterate through rewards
            for rwd = [0,1]
                idx = find(...
                    mdp_dynamics.("s") == ss & ...
                    mdp_dynamics.("s'") == sp & ...
                    mdp_dynamics.("r") == rwd);
                if isempty(idx)
                    continue;
                end
                
                Vs = Vs + ...
                    mdp_dynamics.("p(s',r | s)")(idx) * ...
                    (rwd + gamma * value_function(sp));
            end
        end
        
        % update state-value function
        value_function(ss) = Vs;
        
        % check if evaluation is finished
        delta = max(delta,abs(Vs - temp));
    end
    
    % progress report
    fprintf('delta = %.2e\n',delta);
    iter = iter + 1;
    if mod(iter,10) == 0
        plot(iri_edges,value_function,...
            'linewidth',1);
        set(gca,...
            'colororder',winter(iter/10));
        drawnow;
    end
end

% annotate gamma
text(.05,1,sprintf('\\gamma = %.3f',gamma),...
    'units','normalized');
text(.05,.975,sprintf('\\eta = %.3f s',etafun(dt,gamma)),...
    'units','normalized');

% color bar
clrbar = colorbar;
clrlabel.string = 'estimation stage';
clrlabel.fontsize = axesopt.fontsize * 1.1;
clrlabel.rotation = 270;
set(clrbar,...
    clrbaropt,...
    'ticks',[0,1],...
    'ticklabels',{'early on','later'},...
    'ticklength',.005,...
    'fontsize',axesopt.fontsize);
set(clrbar.Label,...
    clrlabel);
return;

%%
figure(figopt,...
    'windowstyle','normal');
axes(axesopt,...
    'plotboxaspectratio',[1,1,1],...
    'fontsize',12,...
    'xlim',[-3.23,3.58],...
    'ylim',[-4.02,11.34],...
    'xtick',[],...
    'ytick',[],...
    'layer','bottom');
xlabel('x (a.u.)');
ylabel('y (a.u.)');

rng(0);
m = 1e3;
betas = [1.5;.5];
x = randn(m,1);
X = x .^ [1,2];
y = X * betas + randn(m,1);

h = floor(.01 * m);
% x(randperm(m,h)) = normrnd(mean(x),1);
y(randperm(m,h)) = normrnd(7.5,1,h,1);

grapeplot(x,y,...
    'marker','o',...
    'markerfacecolor',[1,1,1],...
    'markeredgecolor',[0,0,0],...
    'markersize',6,...
    'linewidth',1.5);

betas_hat = [-2;0];
betas_hat = X.*[1,1] \ y;
xx = linspace(min(xlim),max(xlim),m)';
y_hat = xx .^ [1,2] * betas_hat;
y_hat(y_hat < min(ylim) | y_hat > max(ylim)) = nan;
p = plot(xx,y_hat,...
    'color',[.85,.05,.15],...
    'linewidth',2);

xlim(xlim+[-1,1]*.05*range(xlim));
ylim(ylim+[-1,1]*.05*range(ylim));

save_path = 'C:\Users\flipe\Desktop\retreat';
svg_file = fullfile(save_path,['poly','.svg']);
print(gcf,svg_file,'-dsvg','-painters');