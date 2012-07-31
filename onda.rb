#!/home/flus/.rvm/rubies/ruby-1.9.3-p194/bin/ruby
require 'gnuplot.rb'

class Ponto

	attr_accessor :tempo, :pwm, :gpio

	def initialize(t,x,y)
		@tempo = (Float(t)*1000000).round(3)
		@pwm = Float(x)
		@gpio = Float(y)
	end

	def <=>(a)
		@tempo <=> a.tempo
	end
end

class Medidas

	attr_accessor :pontos

	def initialize(filename)
		File.open filename do |infile|
			@pontos = []
			infile.readline
			infile.readline
			infile.each_line do |line|
				t,x,y = line.split(",")
				ponto = Ponto.new(t,x,y);
				@pontos << ponto
			end
		end
	end
	
	def gpio
		[[0,1]] + @pontos.each_cons(2).collect { |x,y| interval = y.gpio - x.gpio; interval>1 ? [y.tempo,1] : interval<-1 ? [y.tempo,0] : nil }.select { |x| x }
	end
	
	def pwm
		[[0,1]] + @pontos.each_cons(2).collect { |x,y| interval = y.pwm - x.pwm; interval>1 ? [y.tempo,1] : interval<-1 ? [y.tempo,0] : nil }.select { |x| x }
	end

	def timer_is
		if @pontos[0].pwm > 1 && @pontos[0].gpio > 1
			latency = nil
			skipped = false;
			interval = nil
			timer_is = []
			skip = false;
			miss = 0;
			@pontos.each_cons(3).each do |x,v,y|
				int_pwm = y.pwm - x.pwm
				int_gpio = y.gpio - x.gpio
				
				if skip
					skip = false
				elsif latency.nil?
					if int_gpio < -1
						latency = y.tempo
					end
				elsif !skipped
					if int_pwm < -1
						skipped = true
						skip = true;
					end
				elsif interval.nil?
					if int_pwm > 1 || int_pwm < -1
						interval = y.tempo
					end
				else
					if int_gpio > 1 || int_gpio < -1
						temp = y.tempo - interval
						if temp >= 20
							miss += (temp/20).to_i
						else
							timer_is << temp
						end
						interval = nil
					end
				end
			end
			[[latency],timer_is,miss]
		end
	end

	def [](a)
		@pontos[a]
	end

	def plot
		Gnuplot.open do |gp|
			Gnuplot::Plot.new(gp) do |plot|
				plot.output "onda.pdf"
				plot.terminal "pdf colour size 27cm,19cm"

				plot.xrange "[0:500]"
				plot.yrange "[-2:3]"
				plot.title  "Onda"
				plot.ylabel "Nivel logico"
				plot.xlabel "Tempo"
				x = gpio.collect { |x| x[0] }.each_cons(2).collect { |x| x }.flatten
				y = [2] + gpio.collect { |x| x[1]+1 }.each_cons(2).collect { |x| x }.flatten[0..-2]

				plot.data << Gnuplot::DataSet.new([x,y]) do |ds|
					ds.with = "linespoints"
					ds.notitle
				end

				x = pwm.collect { |x| x[0] }.each_cons(2).collect { |x| x }.flatten
				y = [0] + pwm.collect { |x| x[1]-1 }.each_cons(2).collect { |x| x }.flatten[0..-2]

				plot.data << Gnuplot::DataSet.new([x,y]) do |ds|
					ds.with = "linespoints"
					ds.notitle
				end
			end
		end
    end
end

class Media

	attr_accessor :gpio_i, :timer_is, :miss

	def initialize(dirname)
		@dirname = dirname
		@gpio_i,@timer_is,@miss = Dir.entries(dirname).select { |dir| dir =~ /.+\.csv/ }.collect { 
			|file| Medidas.new(dirname + file).timer_is }.inject {
			|total,med| [total[0] + med[0], total[1] + med[1], total[2] + med[2]] }
	end
	
	def gpio_i_max
		@gpio_i.inject { |max,lat| max > lat ? max : lat }
	end
	
	def gpio_i_min
		@gpio_i.inject { |min,lat| min < lat ? min : lat }
	end

	def gpio_i_media
		@gpio_i.inject(:+)/@gpio_i.length
	end
	
	def timer_is_max
		@timer_is.inject { |max,lat| max > lat ? max : lat }
	end
	
	def timer_is_min
		@timer_is.inject { |min,lat| min < lat ? min : lat }
	end

	def timer_is_media
		@timer_is.inject(:+)/@timer_is.length
	end
	
    def gpio_i_desvio
      m = gpio_i_media
      sum = gpio_i.inject(0){|accum, i| accum +(i-m)**2 }
      Math.sqrt(sum/(timer_is.length - 1))
    end

    def timer_is_desvio
      m = timer_is_media
      sum = timer_is.inject(0){|accum, i| accum +(i-m)**2 }
      Math.sqrt(sum/(timer_is.length - 1))
    end

    def gpio_i_variancia
      "#{(gpio_i_media-gpio_i_desvio).round(2)}-#{(gpio_i_media+gpio_i_desvio).round(2)}"
    end

    def timer_is_variancia
      "#{(timer_is_media-timer_is_desvio).round(2)}-#{(timer_is_media+timer_is_desvio).round(2)}"
    end

	def to_s
		<<-EOF
Medicoes: #{@dirname}
		
GPIO_I max: #{gpio_i_max}
GPIO_I min: #{gpio_i_min}
GPIO_I media: #{gpio_i_media.round(2)}
GPIO_I desvio: #{gpio_i_desvio.round(2)}
GPIO_I variancia: #{gpio_i_variancia}

Timer_I max: #{timer_is_max}
Timer_I min: #{timer_is_min}
Timer_I medio: #{timer_is_media.round(2)}
Timer_I desvio: #{timer_is_desvio.round(2)}
Timer_I variancia: #{timer_is_variancia}

Interrupcoes perdidas: #{miss}

		EOF
	end
end

puts(Media.new("onda_linux/20us/no_carga/"))
puts(Media.new("onda_linux/20us/carga/"))

puts(Media.new("onda_qnx/20us/no_carga/"))
puts(Media.new("onda_qnx/20us/carga/"))
	
puts(Media.new("onda_fiasco/20us/no_carga/"))
puts(Media.new("onda_fiasco/20us/carga/"))
