module OptimalColor

import Base.@kwdef
using LinearAlgebra
using JuMP
using Ipopt
using Crayons
using Plots
using Printf
using DataFrames

dist(x) =  abs(x[1]) + abs(x[2]) +  abs(x[3])

# %%
# toCIELAB 関数の定義
transmat = [
0.49 0.31 0.20
0.17697 0.81240 0.01063
0 0.01 0.99
]
function modifiedCubicRoot(t)
    if t >= (6 / 29)^3
        return t^(1/3)
    else
        return (1/3) * (29/6)^2 * t + 4 / 29
    end
end
function toCIELAB_L(r, g, b)
    v = transmat * [r, g, b]
    L = 116 * modifiedCubicRoot(v[2]) - 16
    # a = 500 * (modifiedCubicRoot(v[1]) - modifiedCubicRoot(v[2]))
    # b = 200 * (modifiedCubicRoot(v[2]) - modifiedCubicRoot(v[3]))
    return L
end
function toCIELAB_a(r, g, b)
    v = transmat * [r, g, b]
    a = 500 * (modifiedCubicRoot(v[1]) - modifiedCubicRoot(v[2]))
    return a
end
function toCIELAB_b(r, g, b)
    v = transmat * [r, g, b]
    b = 200 * (modifiedCubicRoot(v[2]) - modifiedCubicRoot(v[3]))
    return b
end
function huevec(r, g, b)
    a = toCIELAB_a(r, g, b)
    b = toCIELAB_b(r, g, b)
    return [a, b]
end
toCIELAB(r, g, b) = [toCIELAB_L(r, g, b), toCIELAB_a(r, g, b), toCIELAB_b(r, g, b)]

@kwdef struct ModelConfig
    # n_bg: 欲しい background color の数 (base 除く)
    n_bg # = 3
    # n_fg: 欲しい foreground color の数 (base 除く)
    n_fg # = 8
    # bbase と f、b と fbase の間に担保される L* の差（視認性の担保）
    d_vivid_base # = 34
    # f、b 間に担保される L* の差（視認性の担保）
    d_vivid_colored # = 30
    # margin: 純色（RGB 色空間の境界面に位置する色）を避けるため、
    #         RGB 色空間の端に設けるマージン。
    margin # = 24 / 255
    # b が満たすべき色相の差（色相の多様性の担保）
    min_theta_bg # = 70 * π / 180
    # f が満たすべき色相の差（色相の多様性の担保）
    min_theta_fg # = 40 * π / 180
    # b 同士の Lab 色空間上における最低距離（識別性の担保）
    min_dist_b # = 33
    # f 同士の Lab 色空間上における最低距離（識別性の担保）
    min_dist_f # = 26
    # colorscheme の種類。dark なら1、 light なら-1
    is_dark
end

function new_model(model_config::ModelConfig)
    n_bg = model_config.n_bg
    n_fg = model_config.n_fg
    d_vivid_base = model_config.d_vivid_base
    d_vivid_colored = model_config.d_vivid_colored
    margin = model_config.margin
    min_theta_bg = model_config.min_theta_bg
    min_theta_fg = model_config.min_theta_fg
    min_dist_b = model_config.min_dist_b
    min_dist_f = model_config.min_dist_f
    is_dark = model_config.is_dark

    model = Model(Ipopt.Optimizer)

    # %%
    # n_bg 種類のRGB背景色（margin を考慮した 0 から 1 に定義域を束縛）
    @variable(model, margin <= bbase <= 1 - margin)
    @variable(model, margin <= fbase <= 1 - margin)
    @variable(model, margin <= b[i=1:n_bg, j=1:3] <= 1 - margin)
    # n_fg 種類のRGB背景色（margin を考慮した 0 から 1 に定義域を束縛）
    @variable(model, margin <= f[i=1:n_fg, j=1:3] <= 1 - margin)

    # %%
    # 関数の登録
    register(model, :toCIELAB_L, 3, toCIELAB_L; autodiff = true)
    register(model, :toCIELAB_a, 3, toCIELAB_a; autodiff = true)
    register(model, :toCIELAB_b, 3, toCIELAB_b; autodiff = true)

    # %% [markdown]
    """
    ### 必ず入れる制約条件
    """

    # %%
    # 任意の i, j について、背景色 b_i、文字色 f_j の場合の視認性を担保
    for i in 1:n_bg
        for j in 1:n_fg
            @NLconstraint(model,
            is_dark * (toCIELAB_L(f[j, 1], f[j, 2], f[j, 3]) - toCIELAB_L(b[i, 1], b[i, 2], b[i, 3])) >= d_vivid_colored
            )
        end
    end
    for i in 1:n_fg
        @NLconstraint(model,
        is_dark * (toCIELAB_L(f[i, 1], f[i, 2], f[i, 3]) - toCIELAB_L(bbase, bbase, bbase)) >= d_vivid_base
        )
    end

    for i in 1:n_bg
        @NLconstraint(model,
        is_dark * (toCIELAB_L(fbase, fbase, fbase) - toCIELAB_L(b[i, 1], b[i, 2], b[i, 3])) >= d_vivid_base
        )
    end

    @NLconstraint(model,
    is_dark * (toCIELAB_L(fbase, fbase, fbase) - toCIELAB_L(bbase, bbase, bbase)) >= d_vivid_colored
    )

    # %%
    # 任意の i, j (i ≂̸ j) において、b_i, b_j 間の距離は min_dist_b 以上（識別性最大化）
    for i in 1:n_bg
        for j in 1:n_bg
            if i != j
                @NLconstraint(model,
                (toCIELAB_L(b[j, 1], b[j, 2], b[j, 3]) - toCIELAB_L(b[i, 1], b[i, 2], b[i, 3])) ^ 2
                + (toCIELAB_a(b[j, 1], b[j, 2], b[j, 3]) - toCIELAB_a(b[i, 1], b[i, 2], b[i, 3])) ^ 2
                + (toCIELAB_b(b[j, 1], b[j, 2], b[j, 3]) - toCIELAB_b(b[i, 1], b[i, 2], b[i, 3])) ^ 2
                >= (min_dist_b) ^ 2
                )
            end
        end
        @NLconstraint(model,
        (toCIELAB_L(bbase, bbase, bbase) - toCIELAB_L(b[i, 1], b[i, 2], b[i, 3])) ^ 2
        + (toCIELAB_a(bbase, bbase, bbase) - toCIELAB_a(b[i, 1], b[i, 2], b[i, 3])) ^ 2
        + (toCIELAB_b(bbase, bbase, bbase) - toCIELAB_b(b[i, 1], b[i, 2], b[i, 3])) ^ 2
        >= (min_dist_b) ^ 2
        )
    end

    # 任意の i, j (i ≂̸ j) において、f_i, f_j 間の距離は min_dist_f 以上（識別性最大化）
    for i in 1:n_fg
        for j in 1:n_fg
            if i != j
                @NLconstraint(model,
                (toCIELAB_L(f[j, 1], f[j, 2], f[j, 3]) - toCIELAB_L(f[i, 1], f[i, 2], f[i, 3])) ^ 2
                + (toCIELAB_a(f[j, 1], f[j, 2], f[j, 3]) - toCIELAB_a(f[i, 1], f[i, 2], f[i, 3])) ^ 2
                + (toCIELAB_b(f[j, 1], f[j, 2], f[j, 3]) - toCIELAB_b(f[i, 1], f[i, 2], f[i, 3])) ^ 2
                >= (min_dist_f) ^ 2
                )
            end
        end
        @NLconstraint(model,
        (toCIELAB_L(fbase, fbase, fbase) - toCIELAB_L(f[i, 1], f[i, 2], f[i, 3])) ^ 2
        + (toCIELAB_a(fbase, fbase, fbase) - toCIELAB_a(f[i, 1], f[i, 2], f[i, 3])) ^ 2
        + (toCIELAB_b(fbase, fbase, fbase) - toCIELAB_b(f[i, 1], f[i, 2], f[i, 3])) ^ 2
        >= (min_dist_f) ^ 2
        )
    end

    # %% [markdown]
    """
    ### お好みで入れる制約条件

    他の拘束条件と矛盾しないように注意（実行可能解が無くなると最適化が適切に行われない）
    """

    # %%
    # 任意の i, j (i ≂̸ j) において、色同士の色相（角度）差が min_theta 以上
    function diff_hue(x1, x2, x3, y1, y2, y3, θ)
        x = huevec(x1, x2, x3)
        y = huevec(y1, y2, y3)
        return (norm(x) * norm(y) * cos(θ)) - (x ⋅ y)
    end
    register(model, :diff_hue, 7, diff_hue; autodiff = true)
    for i in 1:n_bg
        for j in 1:n_bg
            if i != j
                @NLconstraint(
                model,
                diff_hue(b[i, 1], b[i, 2], b[i, 3], b[j, 1], b[j, 2], b[j, 3], min_theta_bg) >= 0
                )
            end
        end
    end
    for i in 1:n_fg
        for j in 1:n_fg
            if i != j
                @NLconstraint(
                model,
                diff_hue(f[i, 1], f[i, 2], f[i, 3], f[j, 1], f[j, 2], f[j, 3], min_theta_fg) >= 0
                )
            end
        end
    end

    return model
end

export ModelConfig, new_model, toCIELAB

end # module
