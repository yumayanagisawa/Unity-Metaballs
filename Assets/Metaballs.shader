Shader "Unlit/Metaballs"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
		iChannel0("Texture iChannel0", Cube) = "white" {}
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            // make fog work
            #pragma multi_compile_fog

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                UNITY_FOG_COORDS(1)
                float4 vertex : SV_POSITION;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                UNITY_TRANSFER_FOG(o,o.vertex);
                return o;
            }
			// if you change this, try making it a square number (1,4,9,16,25,...)
			#define samples 4

			#define numballs 8

			// undefine this for numerical normals
			#define ANALYTIC_NORMALS

			samplerCUBE iChannel0;


			float hash1(float n)
			{
				return frac(sin(n)*43758.5453123);
			}

			float2 hash2(float n)
			{
				return frac(sin(float2(n, n + 1.0))*float2(43758.5453123, 22578.1459123));
			}

			float3 hash3(float n)
			{
				return frac(sin(float3(n, n + 1.0, n + 2.0))*float3(43758.5453123, 22578.1459123, 19642.3490423));
			}

			//----------------------------------------------------------------

			float4 blobs[numballs];

			float sdMetaBalls(float3 pos)
			{
				float m = 0.0;
				float p = 0.0;
				float dmin = 1e20;

				float h = 1.0; // track Lipschitz constant

				for (int i = 0; i < numballs; i++)
				{
					// bounding sphere for ball
					float db = length(blobs[i].xyz - pos);
					if (db < blobs[i].w)
					{
						float x = db / blobs[i].w;
						p += 1.0 - x * x*x*(x*(x*6.0 - 15.0) + 10.0);
						m += 1.0;
						h = max(h, 0.5333*blobs[i].w);
					}
					else // bouncing sphere distance
					{
						dmin = min(dmin, db - blobs[i].w);
					}
				}
				float d = dmin + 0.1;

				if (m > 0.5)
				{
					float th = 0.2;
					d = h * (th - p);
				}

				return d;
			}

			float3 norMetaBalls(float3 pos)
			{
				float3 nor = float3(0.0, 0.0001, 0.0);

				for (int i = 0; i < numballs; i++)
				{
					float db = length(blobs[i].xyz - pos);
					float x = clamp(db / blobs[i].w, 0.0, 1.0);
					float p = x * x*(30.0*x*x - 60.0*x + 30.0);
					nor += normalize(pos - blobs[i].xyz) * p / blobs[i].w;
				}

				return normalize(nor);
			}


			float map(in float3 p)
			{
				return sdMetaBalls(p);
			}


			static const float precis = 0.01;

			float2 intersect(in float3 ro, in float3 rd)
			{
				//float maxd = 10.0;
				float maxd = 15.0;
				float h = precis * 2.0;
				float t = 0.0;
				float m = 1.0;
				for (int i = 0; i < 75; i++)
				{
					if (h<precis || t>maxd) continue;//break;
					t += h;
					h = map(ro + rd * t);
				}

				if (t > maxd) m = -1.0;
				return float2(t, m);
			}

			float3 calcNormal(in float3 pos)
			{
				#ifdef ANALYTIC_NORMALS	
					return norMetaBalls(pos);
				#else	
					float3 eps = float3(precis, 0.0, 0.0);
					return normalize(vec3(
						map(pos + eps.xyy) - map(pos - eps.xyy),
						map(pos + eps.yxy) - map(pos - eps.yxy),
						map(pos + eps.yyx) - map(pos - eps.yyx)));
				#endif
			}

            fixed4 frag (v2f i) : SV_Target
            {
				//-----------------------------------------------------
				// input
				//-----------------------------------------------------
				//i.uv.x = 1.0 - i.uv.x;

				//vec2 q = fragCoord.xy / iResolution.xy;
				float2 q = i.uv;

				float2 m = float2(0.5, 0.5);
				//if (iMouse.z > 0.0) m = iMouse.xy / iResolution.xy;

				//-----------------------------------------------------
				// montecarlo (over time, image plane and lens) (5D)
				//----------j-------------------------------------------

				float msamples = sqrt(float(samples));

				float3 tot = float3(0.0, 0.0, 0.0);
				#if samples>1
				for (int a = 0; a < samples; a++)
				#else
				float a = 0.0;
				#endif		
				{
					float2  poff = float2(fmod(float(a), msamples), floor(float(a) / msamples)) / msamples;
				#if samples>4
					float toff = 0.0;
				#else
					float toff = 0.0*(float(a) / float(samples)) * (0.5 / 24.0); // shutter time of half frame
				#endif

				//-----------------------------------------------------
				// animate scene
				//-----------------------------------------------------
					float time = _Time.y + toff;

					// move metaballs
					for (int i = 0; i < numballs; i++)
					{
						float h = float(i) / 8.0;
						blobs[i].xyz = 2.0*sin(6.2831*hash3(h*1.17) + hash3(h*13.7)*time);
						blobs[i].w = 1.7 + 0.9*sin(6.28*hash1(h*23.13));
					}

					// move camera		
					float an = 0.5*time - 6.2831*(m.x - 0.5);
					float3 ro = float3(5.0*sin(an), 2.5*cos(0.4*an), -8.0*cos(an));
					float3 ta = float3(0.0, 0.0, 0.0);

					//-----------------------------------------------------
					// camera
					//-----------------------------------------------------
					// image plane		
					//float2 p = -1.0 + 2.0 * (fragCoord.xy + poff) / iResolution.xy;
					float2 p = -1.0 + 2.0 * (q*_ScreenParams.xy + poff) / _ScreenParams.xy;
					p.x *= _ScreenParams.x / _ScreenParams.y;
					p.x *= -1;
					// camera matrix
					float3 ww = normalize(ta - ro);
					float3 uu = normalize(cross(ww, float3(0.0, 1.0, 0.0)));
					float3 vv = normalize(cross(uu, ww));
					// create view ray
					float3 rd = normalize(p.x*uu + p.y*vv + 2.0*ww);
					// dof
					#if samples >= 9
					float3 fp = ro + rd * 5.0;
					float2 le = -1.0 + 2.0*hash2(dot(i.uv * _ScreenParams.xy, float2(131.532, 73.713)) + float(a)*121.41);
					ro += (uu*le.x + vv * le.y)*0.1;
					rd = normalize(fp - ro);
					#endif		

					//-----------------------------------------------------
					// render
					//-----------------------------------------------------

					// background
					//iChannel0.x = 1.0 - iChannel0.x;
					float3 col = pow(texCUBE(iChannel0, rd).xyz, float3(2.2, 2.2, 2.2));
					//float3 col = texCUBE(iChannel0, rd).xyz;

					// raymarch
					float2 tmat = intersect(ro, rd);
					if (tmat.y > -0.5)
					{
						// geometry
						float3 pos = ro + tmat.x*rd;
						float3 nor = calcNormal(pos);
						float3 ref = reflect(rd, nor);

						// materials
						float3 mate = float3(0.0, 0.0, 0.0);
						float w = 0.01;
						for (int i = 0; i < numballs; i++)
						{
							float h = float(i) / 8.0;

							// metaball color
							float3 ccc = float3(1.0, 1.0, 1.0);
							//ccc = lerp(ccc, float3(1.0, 0.60, 0.05), smoothstep(0.65, 0.66, sin(30.0*h)));
							ccc = lerp(ccc, float3(1.0, 0.20, 0.55), smoothstep(0.65, 0.66, sin(30.0*h)));
							//ccc = lerp(ccc, float3(0.3, 0.45, 0.25), smoothstep(0.65, 0.66, sin(15.0*h)));
							ccc = lerp(ccc, float3(0.3, 0.20, 0.95), smoothstep(0.65, 0.66, sin(15.0*h)));

							float x = clamp(length(blobs[i].xyz - pos) / blobs[i].w, 0.0, 1.0);
							float p = 1.0 - x * x*(3.0 - 2.0*x);
							mate += p * ccc;
							w += p;
						}
						mate /= w;

						// lighting
						float3 lin = float3(0.0, 0.0, 0.0);
						lin += lerp(float3(0.05, 0.02, 0.0), 1.2*float3(0.8, 0.9, 1.0), 0.5 + 0.5*nor.y);
						lin *= 1.0 + 1.5*float3(0.7, 0.5, 0.3)*pow(clamp(1.0 + dot(nor, rd), 0.0, 1.0), 2.0);
						//lin += 1.5*clamp(0.3 + 2.0*nor.y, 0.0, 1.0)*pow(texCUBE(iChannel0, ref).xyz, float3(2.2, 2.2, 2.2))*(0.04 + 0.96*pow(clamp(1.0 + dot(nor, rd), 0.0, 1.0), 4.0));
						lin += 1.5*clamp(0.3 + 2.0*nor.y, 0.0, 1.0)*pow(texCUBE(iChannel0, ref).xyz, float3(2.2, 2.2, 2.2))*(0.04 + 0.96*pow(clamp(1.0 + dot(nor, rd), 0.0, 1.0), 4.0));

						// surface-light interacion
						col = lin * mate;
					}
					tot += col;
				}
				tot /= float(samples);
				
				//-----------------------------------------------------
				// postprocessing
				//-----------------------------------------------------
				// gamma
				tot = pow(clamp(tot, 0.0, 1.0), float3(0.45, 0.45, 0.45));

				// vigneting
				tot *= 0.5 + 0.5*pow(16.0*q.x*q.y*(1.0 - q.x)*(1.0 - q.y), 0.15);
				//fragColor = 
				return float4(tot, 1.0);
            }
            ENDCG
        }
    }
}
