function solution = tls_point_cloud_registration_denseSOS(problem)
    % use dense SOS relaxation to solve point cloud registration
    % with TLS
    % Heng Yang
    % 03/23/2020
    yalmip('clear')
    % copy data
    N = problem.N;
    cloudA = problem.cloudA;
    cloudB = problem.cloudB;
    noiseBoundSq = problem.noiseBoundSq;
    barc2 = 1; % since the residuals are normalized, barc2 is always 1
    translationBound = problem.translationBound;
    % define decision variables
    % NOTE: I tried using unit quaternion to represent rotation, but it
    % failed, that's why I switched to rotation matrix -- HY
    t0 = tic;
    r = sdpvar(9,1);
    R = reshape(r,[3,3]);
    r1 = R(:,1); r2 = R(:,2); r3 = R(:,3);
    t = sdpvar(3,1);
    theta = sdpvar(N,1);
    % calculate residuals for each pair of measurements
    residuals = {};
    for i = 1:N
        ai = cloudA(:,i);
        bi = cloudB(:,i);
        residual = bi'*bi + ai'*ai + t'*t - 2*bi'*R*ai - 2*bi'*t + 2*t'*R*ai;
        residuals{end+1} = residual / noiseBoundSq;
    end
    % compute the objective function
    f_cost = 0;
    for i = 1:N
        fi = (1 + theta(i))/2 * residuals{i} + (1 - theta(i))/2 * barc2;
        f_cost = f_cost + fi;
    end
    % define my feasible set
    calX = [r1'*r1 - 1 == 0;...
            r2'*r2 - 1 == 0;...
            r3'*r3 - 1 == 0;...
            r1'*r2 == 0;...
            r2'*r3 == 0;...
            r3'*r1 == 0;...
            cross(r1,r2) - r3 == 0;...
            cross(r2,r3) - r1 == 0;...
            cross(r3,r1) - r2 == 0;...
            translationBound^2 - t'*t >= 0];
    for i = 1:N
        calX = [calX; theta(i)^2 - 1 == 0];
    end
    
    %%%%%%%%%%%%%%%%%%%%%% No Sparsity %%%%%%%%%%%%%%%%%%%%%%%%%%%
    % derive the moment relaxation
    relaxOrder = 2;
    [conRelaxed,objRelaxed,momentMat] = momentmodel(calX,f_cost,relaxOrder);
    t_relax = toc(t0); % this is the time used to generate the relaxation
    % solve the resulting SDP
    options = sdpsettings('solver', 'mosek', 'verbose', 1, 'debug',1);
    optimize(conRelaxed,objRelaxed,options);
    t_sdp = toc(t0) - t_relax; % this is the time used to solve the SDP
    
    % extract solutions and do certification
    f_sdp = value(objRelaxed);
    momentMat_val={};
    for i = 1:length(momentMat)
        momentMat_val{i} = value(momentMat{i});
    end
    
    M1 = momentMat_val{2};
    M2 = momentMat_val{3};
    rank_moment(1) = rank(M1,1e-3);
    rank_moment(2) = rank(M2,1e-3);
    
    [V,~] = eig(M1);
    v_monomials = V(:,end);
    v_monomials = v_monomials/v_monomials(1);
    r_est = v_monomials(2:10);
    R_est = project2SO3( reshape(r_est,[3,3]) );
    r_est = R_est(:);
    t_est = v_monomials(11:13);
    theta_raw = v_monomials(14:end);
    theta_est = theta_raw;
    theta_est(theta_est<0) = -1;
    theta_est(theta_est>0) = 1;
    f_est = replace(f_cost,[r;t;theta],[r_est;t_est;theta_est]);
    absDualityGap = abs(f_est - f_sdp);
    relDualityGap = absDualityGap / abs(f_est);
   
    % log data into solution structure
    solution.type = 'TLS';
    solution.useSparsity = false;
    solution.f_est = f_est;
    solution.f_sdp = f_sdp;
    solution.relaxOrder = relaxOrder;
    solution.absDualityGap = absDualityGap;
    solution.relDualityGap = relDualityGap;
    solution.R_est = R_est;
    solution.t_est = t_est;
    solution.theta_est = theta_est;
    solution.theta_raw = theta_raw;
    solution.Moments = momentMat_val;
    solution.rank_moment = rank_moment;
    solution.t_relax = t_relax;
    solution.t_sdp = t_sdp;
    PSDCon_size = size(M2,1);
    solution.PSDCon_size = PSDCon_size;
    allPoints = 1:N;
    solution.detectedOutliers = allPoints(theta_est<0);
    
    % print some info
    fprintf('======================== Dense TLS Relaxation ========================\n')
    fprintf('PSD constraint size:'); fprintf('%d ',PSDCon_size); fprintf('.\n');
    fprintf('f_sdp = %g, f_est = %g, absDualityGap = %g, relDualityGap = %g, rank_moment = ',...
        f_sdp, f_est, absDualityGap, relDualityGap);
    fprintf('%g ',rank_moment);
    fprintf('.\n')
    fprintf('Relaxation time: %g[s], SDP time: %g[s].\n',t_relax,t_sdp);
    fprintf('======================================================================\n')
end