import numpy as np
from matplotlib import pyplot as plt
from matplotlib import animation as plta
import komm

def generate_rand_qam_symbols(N: int, M: int = 4) -> tuple[np.ndarray, np.ndarray]:
  max_m = int(M**(1/2)) - 1
  A = (6/(M-1))**(1/2)
  a = np.array([A*(2*m - max_m) for m in range(max_m+1)])
  b = 1j*a
  S = np.array([i + b for i in a]).flatten()
  return np.random.choice(S, N), S

def create_pulse_train(symbols: np.ndarray, sps: int) -> np.ndarray:
  pulses = np.zeros(len(symbols)*sps, dtype=symbols.dtype)
  pulses[::sps] = symbols
  return pulses

upsample = create_pulse_train

def downsample(signal: np.ndarray, sps: int) -> np.ndarray:
  return signal[::sps]

def _energy_of(s):
  return np.sum(np.abs(s)**2)

def get_sinc_pulse(span: int, sps: int, print_impz: None | str = None) -> np.ndarray:
  min_T = -span/2
  max_T = span/2
  t = np.linspace(min_T, max_T, span*sps + 1)
  h = np.sinc(t)
  if print_impz is not None:
    plt.figure()
    plt.stem(t, h)
    plt.grid(True)
    if print_impz == 'show':
      plt.show()
    else:
      plt.savefig(print_impz)
  return h
    

def get_rc_pulse(beta: float, span: int, sps: int, print_impz: None | str = None) -> np.ndarray:
  assert beta >= 0 and beta <= 1
  min_T = -1 * (span/2)
  max_T = (span/2)
  t = np.linspace(min_T, max_T, span*sps + 1)
  with np.errstate(divide='ignore'):
    h = np.sinc(t) * (np.cos(np.pi*beta*t) / (1 - (2*beta*t)**2))
    # print(h)
    if beta == 0:
      h[h == np.inf] = 0
      h[h == -np.inf] = 0
    else:
      h[h == np.inf] = (beta/2) * np.sin(np.pi/(2*beta))
      h[h == -np.inf] = (beta/2) * np.sin(np.pi/(2*beta))
    # print(h)
    E = np.sum(h**2)
    h /= np.sqrt(E)
  if print_impz is not None:
    plt.figure()
    plt.stem(t, h)
    plt.grid(True)
    plt.savefig(print_impz)
  return h

def get_rrc_pulse(beta: float, span: int, sps: int, print_impz: None | str = None):
  span_tuple = (-span//2, span//2)
  h = komm.RootRaisedCosinePulse(rolloff=beta).taps(samples_per_symbol=sps, span=span_tuple)
  h /= np.linalg.vector_norm(h)
  if print_impz is not None:
    t = np.linspace(span_tuple[0], span_tuple[1], len(h))
    plt.figure()
    plt.plot(t, h)
    plt.grid(True)
    plt.savefig(print_impz)
  return h

def zadoff_chu(N, u: int | None = None, q: int = 0) -> np.ndarray:
  n = np.arange(N)
  u = N-1 if u is None else u
  c = N % 2
  return np.exp(-1j * (np.pi*u*n*(n + c + 2*q))/N)

def cgauss_rv(N:int, mu: float = 0, sigmasq: float = 1) -> np.ndarray:
  """
  Returns a vector with N realizations of a complex Gaussian random variable
  with mean mu and variance sigmasq

  Parameters
  ----------
  N : int
      Number of realizations. This will be the size of the output array.
  mu : float, optional
      Mean of the complex gaussian distribution, by default 0
  sigmasq : float, optional
      Variance of the complex gaussian distribution, by default 1

  Returns
  -------
  np.ndarray
      Array of length N complex numbers with mean mu and variance sigmasq
  """
  sigma = np.sqrt(sigmasq/2)
  real = np.random.normal(mu, sigma, N)
  imag = np.random.normal(mu, sigma, N)
  return real + (1j * imag)

def _pam_set(M):
  return np.array([2*m - (M - 1) for m in range(M)])

def _generate_pam_const(M):
  constellation = _pam_set(M)
  energy = _energy_of(constellation)
  A = np.sqrt(energy/M)
  return constellation/A + 0j

def _generate_psk_const(M, phi):
  angle_between_symbols = (2*np.pi) / M
  symbol_angles = np.arange(0, 2*np.pi, angle_between_symbols) + phi
  return np.exp(1j*symbol_angles)

def _is_power_of_two(n):
  return bool(np.exp2(np.floor(np.log2(n))) == n)

def _is_even(n):
  return bool(n % 2 == 0)

def _generate_qam_const(M):
  n = np.log2(M)
  is_square = _is_even(n) # only powers of two that are square are even powers of two
  max_m = int(np.ceil(np.sqrt(M)))
  S = _pam_set(max_m)
  a = S
  b = S * 1j
  constellation = (a + b[:,np.newaxis]).flatten()
  if is_square:
    A = np.sqrt(3/(2*(M-1)))
  else:
    corner_square = (max_m**2) - M
    corner = int(corner_square**(1/2))
    thresholdh = S[-(corner//2)]
    thresholdl = S[(corner//2)-1]
    keep_in_constellation = ~(((np.real(constellation) >= thresholdh) | (np.real(constellation) <= thresholdl)) &  \
                              ((np.imag(constellation) >= thresholdh) | (np.imag(constellation) <= thresholdl)))
    constellation = constellation[keep_in_constellation]
    Energy = _energy_of(constellation)
    A = 1 / np.sqrt(Energy / M)
  return constellation * A

def get_const(digmod: str, Es: float = 1, **kwargs) -> np.ndarray:
  """
  Generate a constellation diagram representing the digital modulation scheme
  digmod with average energy Es, assuming equiprobable symbols. Currently
  supported modulation schemes include OOK, M-PAM, BPSK/QPSK/M-PSK and M-QAM.

  Parameters
  ----------
  digmod : str
      Digital modulation scheme, accepts one of the following strings:
        "OOK" | "M-PAM" | "BPSK" | "QPSK" | "M-PSK" | "M-QAM"
      where "M" must be a positive integer representing the modulation order.
      Note that the behaviour for M-PAM is unpredictable for odd M. Similarly,
      if M is a power of two but not square, it may not produce correct 
      results. Additionally, for M-PSK only, phi can be passed as a keyword
      argument.
  Es : float, optional
      Average energy per symbol, by default 1
      
  Returns
  -------
  np.ndarray
      Set of all symbols in the requested constellation.

  Raises
  ------
  ValueError
      - If a nonpositive modulation order is requested.
      - If an odd modulation order is requested for M-PAM
  NotImplementedError
      - See digmod for an explanation of what modulation schemes are supported.
  """
  modulation_type = digmod[-3:].upper()
  unit_energy_constellation = np.array([])
  match modulation_type:
    case 'OOK':
      unit_energy_constellation = np.array([np.sqrt(2) + 0j, 0 + 0j])
    case 'PAM':
      M, _ = digmod.split('-')
      if not M.isdecimal() or int(M) % 2 == 1:
        raise ValueError(f'Modulation order for M-PAM must be a positive even integer, not {M}')
      unit_energy_constellation = _generate_pam_const(int(M))
    case 'PSK':
      match digmod[0]:
        case 'B':
          unit_energy_constellation = _generate_psk_const(2, 0)
        case 'Q':
          unit_energy_constellation = _generate_psk_const(4, np.pi/4)
        case _:
          M, _ = digmod.split('-')
          if not M.isdecimal():
            raise ValueError(f'Modulation order for M-PSK must be a positive integer, not {M}')
          M = int(M)
          phi = kwargs.get('phi', 0)
          unit_energy_constellation = _generate_psk_const(M, phi)
    case 'QAM':
      M, _ = digmod.split('-')
      if not M.isdecimal():
        raise ValueError(f'Modulation order for M-QAM must be a positive integer, not {M}')
      M = int(M)
      if not _is_power_of_two(M):
        raise NotImplementedError(f'Currently only square constellations are implemented for QAM, {M = } must be a power of 2')
      unit_energy_constellation = _generate_qam_const(M)
    case _:
      raise NotImplementedError(f"{digmod} is not yet an implemented modulation scheme.  \
                                Please choose from 'OOK', 'M-PAM', 'B/Q/M-PSK', 'M-QAM'.")
  return unit_energy_constellation * np.sqrt(Es)

def _euclidian_distance(a, b):
  return np.abs(a - b)

def get_const_metrics(S: np.ndarray) -> tuple[float, float, int]:
  """
  Calculate various metrics for the input constellation.

  Parameters
  ----------
  S : np.ndarray
      Set of symbols in the constellation

  Returns
  -------
  Es, dmin, M = tuple[float, float, int]
      Es is the average energy per symbol, dmin is the minimum distance between
      distinct symbols, and M is the modulation order associated with the
      constellation.
  """
  M = len(S)
  Es = _energy_of(S) / M
  dmin = np.inf
  for i in range(M):
    for j in range(i):
      dmin = np.minimum(_euclidian_distance(S[i], S[j]), dmin)
  return Es, dmin, M

def gen_rand_symbols(S: np.ndarray, N: int) -> np.ndarray:
  """
  Generate a sequence on N random symbols sampled from S

  Parameters
  ----------
  S : np.ndarray
      Constellation, set of symbols to choose from
  N : int
      Number of symbols to sample

  Returns
  -------
  np.ndarray
      Array of length N containing symbols randomly taken from S
  """
  return np.random.choice(S, N)

def min_dist_detection(y: np.ndarray, S: np.ndarray) -> np.ndarray:
  """
  Returns array of symbols nearest to those in y elementwise.

  Parameters
  ----------
  y : np.ndarray
      Array of arbitrary points in complex plane
  S : np.ndarray
      Constellation, as a set of all symbols

  Returns
  -------
  np.ndarray
      An array of length len(y), where each element is an element in
      S that is nearest to the corresponding element in y
  """
  differences = y[:,np.newaxis] - S
  distances = np.abs(differences)
  return S[np.argmin(distances, axis=1)]

def awgn_ml_detection(z, S):
  # In AWGN has the same outcome as min_dist_detection
  return min_dist_detection(z, S)

def awgn_map_detection(z, S, prior):
  differences = z[:,np.newaxis] - S
  awgn_likelihood = np.exp(-np.abs(differences)**2)/np.pi
  posterior = awgn_likelihood*prior
  return S[np.argmax(posterior, axis=1)]

def calc_error_rate(s1: np.ndarray, s2: np.ndarray) -> float:
  """
  Calculate the fraction of entries in s1 that differ from the
  corresponding entries in s2

  Parameters
  ----------
  s1 : np.ndarray
      Array of complex numbers
  s2 : np.ndarray
      Array of complex numbers

  Returns
  -------
  float
      Fraction of numbers in s1 that are EXACTLY equal to the
      corresponding elements in s2. Both arrays should pull
      from the same set of elements without arithmetic
      operations performed on them to avoid mal-effects of
      floating point error.
  """
  return np.sum(s1 != s2) / len(s1)

def plot_complex_time_sequence(x, fs):
  fig, (ax1, ax2) = plt.subplots(2, 1, sharex=True, sharey=True)
  ax1.set_ylabel('Real')
  ax2.set_ylabel('Imaginary')
  t = np.arange(0, len(x)) / fs
  ax1.plot(t, np.real(x))
  ax2.plot(t, np.imag(x))
  ax1.grid('both')
  ax2.grid('both')
  return fig, ax1, ax2

def plot_constellation(S):
  fig, ax = plt.subplots()
  ax.set_xlabel('Real')
  ax.set_ylabel('Imag')
  plt.scatter(np.real(S), np.imag(S))
  return fig, ax

def animate_complex_sequence(seq, name, file, sps=60):
  fig = plt.figure()
  plot_title = plt.title(f'{name}: Symbol 0')
  symbol = plt.scatter(np.real(seq[0]), np.imag(seq[0]))
  plt.xlabel('Real')
  plt.ylabel('Imaginary')
  plt.grid()
  lim = np.max(np.abs(seq))
  plt.xlim([-1.25*lim, 1.25*lim])
  plt.ylim([-1.25*lim, 1.25*lim])
  def update(frame):
    plot_title.set_text(f'{name}: Symbol {frame}')
    re = np.real(seq[frame])
    imag = np.imag(seq[frame])
    symbol.set_offsets(np.array([[re, imag]]))
    return (plot_title, symbol)
  anim = plta.FuncAnimation(fig=fig, func=update, frames=len(seq), interval=(1e3/sps))
  anim.save(file)

def str2words(s: str, M: int):
  assert M <= 256
  m = int(np.floor(np.log2(M)))
  intstring = np.array([[ord(c) for c in s]], dtype=np.uint8)
  bitstring = np.unpackbits(intstring)
  num_bits = len(bitstring)
  extra_bits = 0 if num_bits % m == 0 else m - (num_bits % m)
  padded_bits = np.pad(bitstring, (0, extra_bits))
  bin_word = np.reshape(padded_bits, (-1, m))
  pad_word = np.pad(bin_word, {0: (0,0), 1: (8-m, 0)})
  words = np.packbits(pad_word, axis=-1)
  return np.squeeze(words)

def words2str(w: np.ndarray, M: int):
  assert M <= 256
  m = int(np.floor(np.log2(M)))
  word_binary_padded = np.reshape(np.unpackbits(w), (-1, 8))[:,8-m:].flatten()
  num_bits = len(word_binary_padded)
  word_binary = word_binary_padded[:num_bits - (num_bits % 8)]
  char_bytes = np.packbits(np.reshape(word_binary, (-1, 8)))
  return "".join(chr(byte) for byte in char_bytes)

def write_mem_file(arr: np.ndarray, word_len: int, frac_len: int, outfile: str, complex: bool = False, sep: str = ""):
  lines = None
  if complex:
    r = arr_to_bin(arr.real, word_len, frac_len)
    i = arr_to_bin(arr.imag, word_len, frac_len)
    lines = [r[n] + sep + i[n] + '\n' for n in range(len(r))]
  else:
    lines = arr_to_bin(arr, word_len, frac_len)
    for i in range(len(lines)):
      lines[i] += '\n'
  with open(outfile, 'w') as file:
    file.writelines(lines)
  
def arr_to_bin(arr, word_len, frac_len):
  arr = np.copy(arr)
  arr *= (2**frac_len) # normalize
  arr = np.trunc(arr)
  arr = np.clip(arr, -1 * 2**(word_len-1), 2**(word_len-1) - 1)
  arr[arr < 0] = arr[arr < 0] + 2**(word_len)
  lines = ['{0:0{width}b}'.format(int(x), width=word_len) for x in arr]
  for i  in range(len(lines)):
    if lines[i].startswith('0'):
      lines[i].replace('0', '1', 1)
    else:
      lines[i].replace('1', '0', 1) # unsigned to signed
  return lines